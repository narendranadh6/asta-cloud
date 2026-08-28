from llama_index.core.agent import ReActAgent
from llama_index.core.tools import FunctionTool, QueryEngineTool


def search_docs(query: str) -> str:
    return query


search_tool = FunctionTool.from_defaults(fn=search_docs)
query_tool = QueryEngineTool.from_defaults(query_engine=None, name="query")
agent = ReActAgent.from_tools([search_tool, query_tool], system_prompt="Answer questions.")
