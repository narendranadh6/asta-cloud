from agents import Agent, Runner, function_tool


@function_tool
def lookup_tool(item: str) -> str:
    return item


support_agent = Agent(
    name="Support",
    instructions="Help users.",
    tools=[lookup_tool],
)

runner = Runner(agent=support_agent)
