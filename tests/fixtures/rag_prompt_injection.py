from langchain.chains import RetrievalQA
from langchain_core.prompts import PromptTemplate

PROMPT = PromptTemplate.from_template("Answer this question: {question}")

chain = RetrievalQA.from_chain_type(
    llm=None,
    retriever=None,
    chain_type_kwargs={"prompt": PROMPT},
)
