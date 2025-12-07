defmodule PouCon.Hardware.DeviceTreeParser do
  def parse(device_tree_string) do
    lines = String.split(device_tree_string, "\n")

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
              if String.starts_with?(value_str, "\"") and String.ends_with?(value_str, "\"") do
                inner = String.slice(value_str, 1..-2//1)
                String.trim(inner)
              else
                value_str
              end

            if key == "" or value == "" do
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
