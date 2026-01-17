defmodule PouCon.Hardware.DataPointTreeParser do
  def parse(data_point_tree_string) do
    lines = String.split(data_point_tree_string, "\n")

    Enum.reduce_while(lines, [], fn line, acc ->
      trimmed = String.trim(line)

      if trimmed == "" do
        {:cont, acc}
      else
        case String.split(trimmed, ":", parts: 2) do
          [key_part, value_part] ->
            key = String.trim(key_part)
            value_str = String.trim(value_part)

            value =
              cond do
                # Handle quoted strings
                String.starts_with?(value_str, "\"") and String.ends_with?(value_str, "\"") ->
                  inner = String.slice(value_str, 1..-2//1)
                  String.trim(inner)

                # Handle boolean values
                value_str in ["true", "True", "TRUE"] ->
                  true

                value_str in ["false", "False", "FALSE"] ->
                  false

                # Handle comma-separated lists (e.g., "temp_1, temp_2, temp_3")
                String.contains?(value_str, ",") ->
                  value_str
                  |> String.split(",")
                  |> Enum.map(&String.trim/1)
                  |> Enum.reject(&(&1 == ""))

                # Default: keep as string
                true ->
                  value_str
              end

            # Check for empty key or empty value (string "" or empty list [])
            empty_value = value == "" or value == []

            if key == "" or empty_value do
              {:halt, {:error, "Invalid key or value in: #{trimmed}"}}
            else
              {:cont, [{String.to_atom(key), value} | acc]}
            end

          _ ->
            {:halt, {:error, "Invalid format (missing or extra colon): #{trimmed}"}}
        end
      end
    end)
    |> case do
      {:error, msg} -> raise ArgumentError, msg
      opts -> opts
    end
  end
end
