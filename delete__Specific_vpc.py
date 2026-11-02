import sys
import time
import boto3
from botocore.exceptions import ClientError

def delete_vpc_and_dependencies(vpc_id, region_name="ap-south-2"):
    ec2_client = boto3.client('ec2', region_name=region_name)
    ec2_res = boto3.resource('ec2', region_name=region_name)
    elbv2_client = boto3.client('elbv2', region_name=region_name)

    print(f"🚀 Initializing deep teardown for VPC: {vpc_id} in {region_name}...")

    # --- 1. DELETE LOAD BALANCERS ---
    print("⏳ Checking for Load Balancers (ALB/NLB)...")
    try:
        lbs = elbv2_client.describe_load_balancers()['LoadBalancers']
        for lb in lbs:
            if lb.get('VpcId') == vpc_id:
                print(f"🔥 Deleting Load Balancer {lb['LoadBalancerArn']}")
                elbv2_client.delete_load_balancer(LoadBalancerArn=lb['LoadBalancerArn'])
                # LBs take time to delete; wait a bit
                time.sleep(10)
    except Exception as e:
        print(f"⚠️ Load balancer check skipped/failed: {e}")

    # --- 2. TERMINATE EC2 INSTANCES ---
    print("⏳ Terminating EC2 Instances...")
    instances = ec2_res.instances.filter(Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}])
    for inst in instances:
        if inst.state['Name'] != 'terminated':
            print(f"🔥 Terminating instance {inst.id}")
            inst.terminate()

    # Wait for instances to fully terminate so ENIs are freed
    for inst in instances:
        if inst.state['Name'] != 'terminated':
            print(f"⏳ Waiting for instance {inst.id} to terminate...")
            inst.wait_until_terminated()

    # --- 3. DELETE VPC PEERING CONNECTIONS ---
    print("⏳ Checking VPC Peering Connections...")
    peerings = ec2_client.describe_vpc_peering_connections(Filters=[
        {'Name': 'requester-vpc-info.vpc-id', 'Values': [vpc_id]}
    ])['VpcPeeringConnections'] + ec2_client.describe_vpc_peering_connections(Filters=[
        {'Name': 'accepter-vpc-info.vpc-id', 'Values': [vpc_id]}
    ])['VpcPeeringConnections']

    for peer in peerings:
        if peer['Status']['Code'] != 'deleted':
            print(f"🔥 Deleting VPC Peering Connection {peer['VpcPeeringConnectionId']}")
            try:
                ec2_client.delete_vpc_peering_connection(VpcPeeringConnectionId=peer['VpcPeeringConnectionId'])
            except ClientError as e:
                print(f"❌ Peer delete error: {e}")

    # --- 4. DELETE VPC ENDPOINTS ---
    print("⏳ Deleting VPC Endpoints...")
    endpoints = ec2_client.describe_vpc_endpoints(Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}])['VpcEndpoints']
    for ep in endpoints:
        print(f"🔥 Deleting VPC endpoint {ep['VpcEndpointId']}")
        ec2_client.delete_vpc_endpoints(VpcEndpointIds=[ep['VpcEndpointId']])

    # --- 5. DELETE NAT GATEWAYS & RELEASE EIPs ---
    print("⏳ Deleting NAT Gateways...")
    nat_gateways = ec2_client.describe_nat_gateways(Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}])['NatGateways']
    nat_eips = []
    for nat in nat_gateways:
        if nat['State'] not in ['deleted', 'deleting']:
            print(f"🔥 Deleting NAT Gateway {nat['NatGatewayId']}")
            for gw_address in nat.get('NatGatewayAddresses', []):
                if 'AllocationId' in gw_address:
                    nat_eips.append(gw_address['AllocationId'])
            ec2_client.delete_nat_gateway(NatGatewayId=nat['NatGatewayId'])

    if nat_gateways:
        print("⏳ Waiting for NAT Gateways to completely delete (this takes a couple of minutes)...")
        while True:
            still_deleting = False
            check_nats = ec2_client.describe_nat_gateways(Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}])['NatGateways']
            for n in check_nats:
                if n['State'] not in ['deleted']:
                    still_deleting = True
            if not still_deleting:
                break
            time.sleep(15)

    # Release EIPs associated with the NAT gateways
    for alloc_id in nat_eips:
        try:
            print(f"🔥 Releasing Elastic IP Allocation ID {alloc_id}")
            ec2_client.release_address(AllocationId=alloc_id)
        except ClientError:
            pass

    # --- 6. DETACH & DELETE NETWORK INTERFACES (ENIs) ---
    print("⏳ Cleaning up Network Interfaces (ENIs)...")
    enis = ec2_client.describe_network_interfaces(Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}])['NetworkInterfaces']
    for eni in enis:
        if 'Attachment' in eni:
            print(f"🔥 Detaching ENI {eni['NetworkInterfaceId']}")
            try:
                ec2_client.detach_network_interface(AttachmentId=eni['Attachment']['AttachmentId'], Force=True)
                time.sleep(2)
            except ClientError:
                pass
        try:
            print(f"🔥 Deleting ENI {eni['NetworkInterfaceId']}")
            ec2_client.delete_network_interface(NetworkInterfaceId=eni['NetworkInterfaceId'])
        except ClientError as e:
            print(f"⚠️ ENI delete deferred (will retry): {e}")

    # --- 7. INTERNET GATEWAYS ---
    vpc = ec2_res.Vpc(vpc_id)
    print("⏳ Detaching and Deleting Internet Gateways...")
    for igw in vpc.internet_gateways.all():
        try:
            igw.detach_from_vpc(VpcId=vpc_id)
            igw.delete()
            print(f"🔥 Removed IGW {igw.id}")
        except ClientError as e:
            print(f"❌ IGW Error: {e}")

    # --- 8. BREAK CYCLIC SECURITY GROUP REFERENCES ---
    print("⏳ Clearing Security Group Rules to break cyclic references...")
    for sg in vpc.security_groups.all():
        if sg.group_name != 'default':
            try:
                if sg.ip_permissions:
                    ec2_client.revoke_security_group_ingress(GroupId=sg.id, IpPermissions=sg.ip_permissions)
                if sg.ip_permissions_egress:
                    ec2_client.revoke_security_group_egress(GroupId=sg.id, IpPermissions=sg.ip_permissions_egress)
            except ClientError as e:
                print(f"⚠️ Could not clear rules for SG {sg.id}: {e}")

    # Delete custom security groups now that rules are gone
    print("⏳ Deleting Custom Security Groups...")
    for sg in vpc.security_groups.all():
        if sg.group_name != 'default':
            try:
                print(f"🔥 Deleting SG {sg.id}")
                sg.delete()
            except ClientError as e:
                print(f"❌ SG Delete Error: {e}")

    # --- 9. ROUTE TABLES ---
    print("⏳ Deleting Route Tables...")
    for rt in vpc.route_tables.all():
        is_main = any(assoc.main for assoc in rt.associations)
        if not is_main:
            try:
                print(f"🔥 Deleting Route Table {rt.id}")
                rt.delete()
            except ClientError as e:
                print(f"❌ Route Table Error: {e}")

    # --- 10. SUBNETS ---
    print("⏳ Deleting Subnets...")
    for subnet in vpc.subnets.all():
        try:
            print(f"🔥 Deleting Subnet {subnet.id}")
            subnet.delete()
        except ClientError as e:
            print(f"❌ Subnet Error: {e}")

    # --- 11. NETWORK ACLs ---
    print("⏳ Deleting Network ACLs...")
    for nacl in vpc.network_acls.all():
        if not nacl.is_default:
            try:
                print(f"🔥 Deleting NACL {nacl.id}")
                nacl.delete()
            except ClientError as e:
                print(f"❌ NACL Error: {e}")

    # --- 12. FINAL VPC REMOVAL ---
    print(f"⚠️ Executing final deletion of VPC {vpc_id}...")
    try:
        vpc.delete()
        print("🎉 Success! The VPC and all hidden dependencies have been permanently removed.")
    except ClientError as e:
        print(f"❌ Failed to delete VPC. AWS reported: {e}")

if __name__ == "__main__":
    # 🔴 REPLACE WITH YOUR DETAILS
    TARGET_VPC = "vpc-0355333e67f14f309"
    AWS_REGION = "ap-south-2"

    delete_vpc_and_dependencies(TARGET_VPC, AWS_REGION)
