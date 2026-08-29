"""Internal SDK patterns that must not be flagged as missing tool allowlists."""


class Model:
    def get_response(
        self,
        system_instructions: str,
        input: object,
        model_settings: object,
        tools: list[object],
        output_schema: object | None,
        handoffs: list[object],
        prompt: object | None = None,
    ) -> object:
        return self._build_response_create_kwargs(
            system_instructions=system_instructions,
            input=input,
            model_settings=model_settings,
            tools=tools,
            output_schema=output_schema,
            handoffs=handoffs,
            prompt=prompt,
        )

    def _build_response_create_kwargs(
        self,
        system_instructions: str,
        input: object,
        model_settings: object,
        tools: list[object],
        output_schema: object | None,
        handoffs: list[object],
        prompt: object | None = None,
    ) -> dict[str, object]:
        return {
            "system_instructions": system_instructions,
            "tools": tools,
            "prompt": prompt,
        }
