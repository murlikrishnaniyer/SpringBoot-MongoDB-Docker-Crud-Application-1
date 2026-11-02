package com.microlcafe.springmongodbcrud.api.model;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

@Document(collection = "Book")
public record Book(
        @Id int id,
        String bookName,
        String authorName
) {
}
