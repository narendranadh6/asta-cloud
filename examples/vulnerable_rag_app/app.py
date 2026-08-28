from pathlib import Path

from langchain.chains import create_retrieval_chain
from langchain_community.document_loaders import DirectoryLoader, WebBaseLoader
from langchain_core.prompts import PromptTemplate

broad_loader = DirectoryLoader("/")

docs = DirectoryLoader(str(Path.home()))


def ingest_user_site(user_url: str) -> list[str]:
    loader = WebBaseLoader(user_url)
    return [doc.page_content for doc in loader.load()]


RAG_PROMPT = PromptTemplate.from_template("Answer the user question: {question}")

chain = create_retrieval_chain(None, None)
