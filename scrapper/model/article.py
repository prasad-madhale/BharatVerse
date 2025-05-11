from pydantic import BaseModel, Field


class Article(BaseModel):
    """
    Represents an article with a title and content.
    """

    title: str = Field(
        ...,
        description="The title of the article.",
    )
    content: str = Field(
        ...,
        description="The content of the article.",
    )
    table_of_contents: dict[str, str] = Field(
        ...,
        description="A dictionary with the sub-section title as keys and their content as values.",
    )
    url: str = Field(
        ...,
        description="The URL of the article.",
    )
    date: str = Field(
        ...,
        description="The date of publication.",
    )
    author: str = Field(
        ...,
        description="The name of the author.",
    )
    tags: list[str] = Field(
        ...,
        description="The keywords associated with the article.",
    )
    references: list[str] = Field(
        ...,
        description="The sources cited in the article.",
    )
