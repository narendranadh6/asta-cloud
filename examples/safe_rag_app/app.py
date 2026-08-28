from langchain_community.document_loaders import TextLoader
from langchain_core.prompts import PromptTemplate

loader = TextLoader("./docs/product_faq.txt")

PROMPT = PromptTemplate.from_template(
    "Context:\n{context}\n\nAnswer using only the context above.\nQuestion: {question}"
)
