Maru::Subscriber.plugin "producers/org.blender.Render" do

  job_type_friendly_name "org.blender.Render", "Blender render"

  producer_task "Render a Blender animation", "blender_animation" do
    form do
      prerequisite ".blend file", :blend_file
      numbers "Frames to render", :frames
      string "Output filename",   :output, example: "####.png, myproj-###.jpg", default: "####.png"
      string "Output format",     :output_format, example: "PNG, JPEG, BMP", default: "PNG"
    end

    generate do |network, params|
      params[:frames].each do |frame|
        network.submit(
          type: 'org.blender.Render',
          destination: params[:destination].with_name("frame #{frame}"),
          description: {
            blend_file_url:    params[:blend_file][:url],
            blend_file_sha256: params[:blend_file][:sha256],

            frame:             frame,
            output:            params[:output],
            output_format:     params[:output_format]
          }
        )
      end
    end
  end

end
