defmodule LogflareWeb.OpenApi do
  alias OpenApiSpex.Schema

  defmacro __using__(properties: properties, required: required) do
    quote do
      require OpenApiSpex

      OpenApiSpex.schema(%{
        type: :object,
        properties: unquote(properties),
        required: unquote(required)
      })

      def response() do
        {"#{__MODULE__.schema().title} Response", "application/json", __MODULE__}
      end

      def params() do
        {"#{__MODULE__.schema().title} Parameters", "application/json", __MODULE__}
      end
    end
  end

  defmodule List do
    def schema(module) do
      %Schema{
        title: "#{module.schema().title}ListResponse",
        type: :array,
        items: module
      }
    end

    def response(module) do
      {
        "#{module.schema().title} List Response",
        "application/json",
        schema(module)
      }
    end
  end

  defmodule One do
    def response(module),
      do: {"#{module.schema().title} One Response", "application/json", module}
  end

  defmodule Created do
    def response(module), do: {"Created Response", "application/json", module}
  end

  defmodule Accepted do
    def schema, do: %Schema{title: "AcceptedResponse"}

    def response(), do: {"Accepted Response", "text/plain", schema()}
    def response(module), do: {"Accepted Response", "application/json", module}
  end

  defmodule NotFound do
    def schema do
      %Schema{
        title: "NotFoundResponse",
        type: :object,
        properties: %{error: %Schema{type: :string}},
        required: [:error]
      }
    end

    def response(), do: {"Not found", "text/plain", schema()}
  end

  defmodule UnprocessableEntity do
    def schema do
      %Schema{
        title: "UnprocessableEntityResponse",
        type: :object,
        properties: %{errors: %Schema{type: :object}},
        required: [:errors]
      }
    end

    def response(), do: {"Unprocessable Entity", "application/json", schema()}
  end

  defmodule BadRequest do
    require OpenApiSpex
    OpenApiSpex.schema(%{})

    def response(), do: {"Bad request", "text/plain", __MODULE__}
  end

  defmodule Unauthorized do
    require OpenApiSpex
    OpenApiSpex.schema(%{})

    def response(), do: {"Unauthorized", "text/plain", __MODULE__}
  end

  defmodule ServerError do
    require OpenApiSpex
    OpenApiSpex.schema(%{})

    def response(), do: {"Server error", "text/plain", __MODULE__}
  end
end
