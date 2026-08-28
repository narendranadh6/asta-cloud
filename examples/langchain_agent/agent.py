from langchain.agents import create_react_agent
from langchain_core.tools import tool


@tool
def weather_tool(city: str) -> str:
    return city


agent = create_react_agent(
  tools=[weather_tool],
  prompt="You are a weather assistant.",
)
