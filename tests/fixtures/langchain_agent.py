from langchain.agents import AgentExecutor, create_react_agent
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.tools import tool
from langchain_openai import ChatOpenAI


@tool
def search_tool(query: str) -> str:
    return query


prompt = ChatPromptTemplate.from_messages([("system", "Be helpful.")])
llm = ChatOpenAI()
agent = create_react_agent(llm, [search_tool], prompt)
executor = AgentExecutor(agent=agent, tools=[search_tool])
