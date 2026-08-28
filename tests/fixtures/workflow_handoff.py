from agents import Agent, handoff

support_agent = Agent(name="support", instructions="Help users")
router = handoff(support_agent)
