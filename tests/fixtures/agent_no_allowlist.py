def search(query: str) -> str:
    return query


class Agent:
    def __init__(self, **kwargs):
        self.kwargs = kwargs


agent = Agent(tools=[search], instructions="Be helpful.")
