from langchain_community.document_loaders import WebBaseLoader


def load_user_page(user_url: str) -> list[str]:
    loader = WebBaseLoader(user_url)
    return [doc.page_content for doc in loader.load()]
