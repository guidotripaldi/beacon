defmodule Beacon.TailwindCompiler do
  @moduledoc """
  Tailwind compiler for runtime CSS, used on all sites.

  The default configuration is fetched from `Path.join(Application.app_dir(:beacon, "priv"), "tailwind.config.js.eex")`,
  you can see the actual file at https://github.com/BeaconCMS/beacon/blob/main/priv/tailwind.config.js.eex

    1. It's recommended to be a file with a .eex file extension

    2. The [content section](https://tailwindcss.com/docs/content-configuration) requires an entry `<%= @beacon_content %>`, eg:

        ```
        content: [
          <%= @beacon_content %>
        ]
        ```

       You're allowed to include more entries per Tailwind specification, but don't remove that special `<%= @beacon_content` placeholder.

  """

  alias Beacon.Components
  alias Beacon.Layouts.Layout
  alias Beacon.Pages
  alias Beacon.Stylesheets

  @behaviour Beacon.RuntimeCSS

  @impl Beacon.RuntimeCSS
  def compile!(%Layout{} = layout) do
    tailwind_config = tailwind_config!(layout.site)

    unless Application.get_env(:tailwind, :version) do
      default_tailwind_version = Beacon.tailwind_version()
      Application.put_env(:tailwind, :version, default_tailwind_version)
    end

    Application.put_env(:tailwind, :beacon_runtime, [])

    tmp_dir = tmp_dir!()

    generated_config_file_path =
      tailwind_config
      |> EEx.eval_file(assigns: %{beacon_content: beacon_content(tmp_dir)})
      |> write_file!(tmp_dir, "tailwind.config.js")

    templates_paths = generate_template_files!(tmp_dir, layout)

    input_css_path = generate_input_css_file!(tmp_dir, layout.site)

    output_css_path = Path.join(tmp_dir, "generated.css")

    exit_code = Tailwind.run(:beacon_runtime, ~w(
      --config=#{generated_config_file_path}
      --input=#{input_css_path}
      --output=#{output_css_path}
      --minify
    ))

    output =
      if exit_code == 0 do
        "/* Generated by #{__MODULE__} at #{DateTime.utc_now()} */" <> "\n" <> File.read!(output_css_path)
      else
        raise "Error running tailwind, got exit code: #{exit_code}"
      end

    cleanup(tmp_dir, [generated_config_file_path, input_css_path, output_css_path] ++ templates_paths)

    output
  end

  defp tailwind_config!(site) do
    tailwind_config = Beacon.Config.fetch!(site).tailwind_config

    if File.exists?(tailwind_config) && File.read!(tailwind_config) =~ "<%= @beacon_content %>" do
      tailwind_config
    else
      raise """
      Tailwind config not found or invalid.

      Make sure the provided file exists at #{inspect(tailwind_config)} and it contains <%= @beacon_content %> in the `content` section.

      See Beacon.Config for more info.
      """
    end
  end

  # TODO: generate by layout or avoid generating unnecessary files
  defp generate_template_files!(tmp_dir, layout) do
    [
      Task.async(fn ->
        layout_path = Path.join(tmp_dir, "layout_#{remove_special_chars(layout.title)}.template")
        File.write!(layout_path, layout.body)
        [layout_path]
      end),
      Task.async(fn ->
        Enum.map(Components.list_components_for_site(layout.site), fn component ->
          component_path = Path.join(tmp_dir, "component_#{remove_special_chars(component.name)}.template")
          File.write!(component_path, component.body)
          component_path
        end)
      end),
      Task.async(fn ->
        Enum.map(Pages.list_pages_for_site(layout.site), fn page ->
          page_path = Path.join(tmp_dir, "page_#{remove_special_chars(page.path)}.template")
          File.write!(page_path, page.template)
          page_path
        end)
      end)
    ]
    |> Task.await_many()
    |> List.flatten()
  end

  # import app css into input css used by tailwind-cli to load tailwind functions and directives
  defp generate_input_css_file!(tmp_dir, site) do
    beacon_tailwind_css_path = Path.join([Application.app_dir(:beacon), "priv", "beacon_tailwind.css"])

    # TODO: generate stylesheets per layout?
    app_css =
      site
      |> Stylesheets.list_stylesheets_for_site()
      |> Enum.map_join(fn stylesheet ->
        ["\n", "/* ", stylesheet.name, " */", "\n", stylesheet.content, "\n"]
      end)

    input_css_path = Path.join(tmp_dir, "input.css")
    File.write!(input_css_path, IO.iodata_to_binary([File.read!(beacon_tailwind_css_path), "\n", app_css]))
    input_css_path
  end

  defp remove_special_chars(name), do: String.replace(name, ~r/[^[:alnum:]_-]+/, "_")

  defp beacon_content(tmp_dir), do: ~s('#{tmp_dir}/*.template')

  defp tmp_dir! do
    tmp_dir = Path.join(System.tmp_dir!(), random_dir())
    File.mkdir_p!(tmp_dir)
    tmp_dir
  end

  defp write_file!(content, tmp_dir, filename) do
    filepath = Path.join(tmp_dir, filename)
    File.write!(filepath, content)
    filepath
  end

  defp random_dir, do: :crypto.strong_rand_bytes(12) |> Base.encode16()

  defp cleanup(tmp_dir, files) do
    Enum.each(files, &File.rm/1)
    File.rmdir(tmp_dir)
  end
end