from agents import Agent, handoff
from langchain.agents import create_react_agent
from langchain.memory import ConversationBufferMemory
from langchain_core.tools import tool

memory = ConversationBufferMemory()
shared_memory = memory

support_agent = Agent(name="support", instructions="Handle support")
billing_agent = Agent(name="billing", instructions="Handle billing")
router = handoff(billing_agent)


@tool
def publish_file(path: str, content: str) -> str:
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)
    return "published"


agent = create_react_agent(llm=None, tools=[publish_file], memory=memory)
