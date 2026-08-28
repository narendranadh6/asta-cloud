from langchain_community.document_loaders import TextLoader
from langchain_core.prompts import PromptTemplate

loader = TextLoader("./docs/readme.txt")

PROMPT = PromptTemplate.from_template(
    "Use this context: {context}\n\nQuestion: {question}"
)
