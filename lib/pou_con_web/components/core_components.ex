defmodule PouConWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label="close">
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :string
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label>
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          phx-hook="SimpleKeyboard"
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">Actions</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  attr :to, :string, required: true
  attr :label, :string, required: true

  def navigate(assigns) do
    ~H"""
    <.link
      navigate={@to}
      replace={true}
      class="inline-flex items-center gap-2 px-4 py-2 bg-gray-300 hover:bg-gray-300 font-medium rounded-md transition"
    >
      {@label}
    </.link>
    """
  end

  attr :labels, :list, default: ["On", "Off"]
  attr :value, :string, required: true
  attr :device, :string, required: true
  attr :click, :string, default: "toggle"
  attr :color, :string, default: "blue"

  def toggle_button(assigns) do
    ~H"""
    <label class="flex flex-col items-center cursor-pointer">
      <input
        type="checkbox"
        class="sr-only peer"
        phx-click={@click}
        phx-value-device={@device}
        checked={@value == Enum.at(@labels, 0)}
      />

      <div class={[
        "relative w-9 h-5 bg-gray-400 peer-focus:outline-none",
        "peer-focus:ring-1 rounded-full peer-checked:after:translate-x-full",
        "rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-['']",
        "after:absolute after:top-[2px] after:start-[2px] after:bg-white",
        "after:border after:rounded-full after:h-4 after:w-4 after:transition-all",
        "peer-focus:ring-#{@color}-300 peer-checked:bg-#{@color}-600 after:border-#{@color}-300"
      ]}>
      </div>
      <div class="mt-1 text-sm font-medium text-gray-900">
        {if @value == Enum.at(@labels, 0), do: Enum.at(@labels, 0), else: Enum.at(@labels, 1)}
      </div>
    </label>
    """
  end

  defp get_device_data({:ok, data}, device_name) do
    data[device_name]
  end

  attr :device_name, :string, required: true
  attr :click, :string, required: true
  attr :data, :any, required: true

  def fan(assigns) do
    onoff_status_device_name = "#{assigns.device_name}_onoff_status"
    a_m_flag_device_name = "#{assigns.device_name}_a_m_flag"
    cmd_status_device_name = "#{assigns.device_name}_cmd_status"

    on_off_status = get_device_data(assigns.data, onoff_status_device_name)
    am_status = get_device_data(assigns.data, a_m_flag_device_name)
    cmd_status = get_device_data(assigns.data, cmd_status_device_name)

    color =
      if cmd_status != on_off_status do
        "rose"
      else
        case on_off_status do
          %{state: 1} -> "green"
          %{state: 0} -> "blue"
          _ -> "gray"
        end
      end

    assigns =
      assigns
      |> assign(:onoff_status_device_name, onoff_status_device_name)
      |> assign(:a_m_flag_device_name, a_m_flag_device_name)
      |> assign(:cmd_status_device_name, cmd_status_device_name)
      |> assign(
        :command_status,
        case cmd_status do
          %{state: 1} -> "On"
          %{state: 0} -> "Off"
          _ -> "error"
        end
      )
      |> assign(
        :auto_manual_status,
        case am_status do
          %{state: 1} -> "Auto"
          %{state: 0} -> "Manual"
          _ -> "error"
        end
      )
      |> assign(
        :on_off_status,
        case on_off_status do
          %{state: 1} -> "On"
          %{state: 0} -> "Off"
          _ -> "error"
        end
      )
      |> assign(:color, color)

    ~H"""
    <div
      id={@device_name}
      class={"h-38 w-20 border-4 bg-#{@color}-200 border-#{@color}-600 rounded-xl p-2"}
    >
      <.toggle_button
        :if={@auto_manual_status != "error"}
        device={@a_m_flag_device_name}
        value={@auto_manual_status}
        labels={["Auto", "Manual"]}
        color={@color}
      />

      <div class={[
        "my-2 ml-3",
        "relative h-8 w-8 rounded-full border-2 border-#{@color}-600",
        (@on_off_status == "On" && "animate-spin") || ""
      ]}>
        <div class="absolute inset-0 flex justify-center">
          <div class={"h-4 w-1 border-2 rounded-full border-#{@color}-600"}></div>
        </div>
        <div class="absolute inset-0 flex justify-center rotate-[120deg]">
          <div class={"h-4 w-1 border-2 rounded-full border-#{@color}-600"}></div>
        </div>
        <div class="absolute inset-0 flex justify-center rotate-[240deg]">
          <div class={"h-4 w-1 border-2 rounded-full border-#{@color}-600"}></div>
        </div>
      </div>

      <.toggle_button
        :if={@auto_manual_status != "Auto" and @on_off_status != "error"}
        device={@cmd_status_device_name}
        value={@command_status}
        labels={["On", "Off"]}
        color={@color}
      />

      <div :if={@auto_manual_status == "Auto"} class="text-center">{@command_status}</div>
    </div>
    """
  end

  attr :device_name, :string, required: true
  attr :data, :any, required: true
  attr :temp_ranges, :list, default: [38.0, 32.0, 24.0]

  def temperature(assigns) do
    {temp, color} =
      case get_device_data(assigns.data, assigns.device_name) do
        %{humidity: _, temperature: x} ->
          {"#{Float.to_charlist(x)}°C",
           cond do
             x >= Enum.at(assigns.temp_ranges, 0) ->
               "rose"

             x < Enum.at(assigns.temp_ranges, 0) and x >= Enum.at(assigns.temp_ranges, 1) ->
               "yellow"

             x <= Enum.at(assigns.temp_ranges, 2) ->
               "blue"

             true ->
               "green"
           end}

        _ ->
          {"ERR", "gray"}
      end

    assigns =
      assigns
      |> assign(:temp, temp)
      |> assign(:color, color)

    ~H"""
    <div class={"text-#{@color}-600 flex"}>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        width="36"
        height="36"
        fill="currentColor"
        viewBox="0 0 16 16"
      >
        <path d="M9.5 12.5a1.5 1.5 0 1 1-2-1.415V6.5a.5.5 0 0 1 1 0v4.585a1.5 1.5 0 0 1 1 1.415" />
        <path d="M5.5 2.5a2.5 2.5 0 0 1 5 0v7.55a3.5 3.5 0 1 1-5 0zM8 1a1.5 1.5 0 0 0-1.5 1.5v7.987l-.167.15a2.5 2.5 0 1 0 3.333 0l-.166-.15V2.5A1.5 1.5 0 0 0 8 1" />
      </svg>
      <span class="text-xl mt-1 -ml-1">{@temp}</span>
    </div>
    """
  end

  attr :device_name, :string, required: true
  attr :data, :any, required: true
  attr :hum_ranges, :list, default: [90.0, 70.0, 40.0]

  def humidity(assigns) do
    {hum, color} =
      case get_device_data(assigns.data, assigns.device_name) do
        %{humidity: x, temperature: _} ->
          {"#{Float.to_charlist(x)}°%",
           cond do
             x >= Enum.at(assigns.hum_ranges, 0) ->
               "rose"

             x < Enum.at(assigns.hum_ranges, 0) and x >= Enum.at(assigns.hum_ranges, 1) ->
               "yellow"

             x <= Enum.at(assigns.hum_ranges, 2) ->
               "rose"

             true ->
               "green"
           end}

        _ ->
          {"ERR", "gray"}
      end

    assigns =
      assigns
      |> assign(:hum, hum)
      |> assign(:color, color)

    ~H"""
    <div class={"text-#{@color}-600 flex"}>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 100 100"
        width="36"
        height="36"
      >
        <path
          d="M50 6 C68 30 88 52 88 72 C88 86 76 94 50 94 C24 94 12 86 12 72 C12 52 32 30 50 6 Z"
          fill="currentColor"
        />
      </svg>
      <span class="text-xl mt-1">{@hum}</span>
    </div>
    """
  end

  # attr :front, :boolean, required: true
  # attr :back, :boolean, required: true
  # attr :forward, :boolean, required: true
  # attr :backward, :boolean, required: true
  # attr :pulse, :boolean, required: true

  def feeding(assigns) do
    ~H"""
    <div class={"text-#{@color}-600 flex"}>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 400 400"
        width="36"
        height="36"
        class="animate-pulse"
      >
        <path
          fill="currentColor"
          d="M264 167c21 11 63 8 94-23 31-31 43-77 13-107l-1-1c-30-29-76-18-107
           13-31 31-35 73-23 94-3 18-27 37-49 49-17-10-38-28-40-65 2-15-3-30-14-41l-4-4L53 19l-7
           7 88 83-10 10L39 34l-8 8 85 85-8 8L23 50l-7 7 85 85-10 10L8 64 0 72l67 85 2 2c10 9 22
           13 34 12h1c32 0 52 20 64 37-30 31-125 126-125 126v1c-8 8-8 20 0 28l2 2c8 8 20 8 28
           0v1s88-88 122-122c32 32 121 121 121 121v-1c8 8 20 8 28 0s8-20 0-28c0 0-98-98-125-125
           12-20 29-41 45-44zm-10-59c0-5 2-11 3-18 1-3 2-6 3-10 2-3 3-6 5-10 4-6 10-11 15-15 5-4 10-7
           15-10 5-2 9-4 12-5 3-1 5-1 5-1s-2 1-4 3c-2 2-5 5-9 8-7 7-17 16-24 26-2 2-3 5-5 8-1 3-3 6-4
           8-2 6-4 11-6 16-2 5-3 9-4 11-1 3-1 5-1 5 0 0-1-2-1-5 0-3-1-7 0-12z"
        />
      </svg>
    </div>
    """
  end

  def filling(assigns) do
    ~H"""
    <div class={"text-#{@color}-600 flex"}>
      <svg
        <svg
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 250 250"
        width="36"
        height="36"
        class="animate-bounce"
      >
        <path
          fill="currentColor"
          d="M74.34 85.66A8 8 0 0 1 85.66 74.34L120 108.69V24a8 8 0 0 1 16
               0v84.69l34.34-34.34a8 8 0 1 1 11.32 11.31l-48
               48c-.02.02-.05.04-.07.06-.17.16-.34.32-.52.47-.1.08-.2.15-.3.22-.11.08-.22.17-.33.24-.12.08-.24.15-.36.22-.1.06-.21.13-.31.19-.12.06-.25.12-.37.18-.11.05-.23.11-.34.16-.12.05-.24.09-.36.13-.13.05-.25.09-.38.13-.12.04-.24.06-.36.09-.13.03-.26.07-.4.1-.14.03-.28.04-.42.06-.12.02-.23.04-.35.05-.27.03-.53.04-.79.04s-.53-.01-.79-.04c-.12-.01-.23-.03-.35-.05-.14-.02-.28-.04-.42-.06-.13-.03-.27-.06-.4-.1-.12-.03-.24-.06-.36-.09-.13-.04-.25-.09-.38-.13-.12-.04-.24-.08-.36-.13-.12-.05-.23-.11-.34-.16-.12-.06-.25-.11-.37-.18-.11-.06-.21-.12-.31-.19-.12-.07-.24-.14-.36-.22-.11-.08-.22-.16-.33-.24-.1-.08-.2-.15-.3-.23-.17-.14-.34-.3-.5-.45-.03-.03-.06-.05-.08-.07ZM240
               136v64a16 16 0 0 1-16 16H32a16 16 0 0 1-16-16v-64a16 16 0 0 1 16-16h54.06l25 25a24 24 0 0 0 33.94 0l25-25H224a16 16 0 0 1 16 16zm-40 32a12 12 0 1 0-12 12 12 12 0 0 0 12-12Z"
        />
      </svg>
    </div>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # You can make use of gettext to translate error messages by
    # uncommenting and adjusting the following code:

    # if count = opts[:count] do
    #   Gettext.dngettext(PouConWeb.Gettext, "errors", msg, msg, count, opts)
    # else
    #   Gettext.dgettext(PouConWeb.Gettext, "errors", msg, opts)
    # end

    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
