# frozen_string_literal: true

module Ragnar
  module CLIVisualization
    def generate_topic_visualization_html(topics, embeddings: nil, cluster_ids: nil)
      # Convert topics to JSON for D3.js
      topics_json = topics.map do |topic|
        topic_data = {
          id: topic.id,
          label: topic.label || "Topic #{topic.id}",
          size: topic.size,
          terms: topic.terms.first(10),
          coherence: topic.coherence,
          samples: topic.representative_docs(k: 2).map { |d| d[0..200] }
        }
        
        # Add summary if it exists
        summary = topic.instance_variable_get(:@summary)
        topic_data[:summary] = summary if summary
        
        topic_data
      end.to_json

      # HTML template with enhanced visualization
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <title>Topic Visualization</title>
          <script src="https://d3js.org/d3.v7.min.js"></script>
          <style>
            body { 
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; 
              margin: 20px;
              background: #f8f9fa;
            }
            .container {
              max-width: 1400px;
              margin: 0 auto;
            }
            h1 {
              color: #2c3e50;
              margin-bottom: 10px;
            }
            .viz-panel {
              background: white;
              border-radius: 8px;
              box-shadow: 0 2px 4px rgba(0,0,0,0.1);
              padding: 15px;
            }
            #bubble-viz {
              height: 500px;
            }
            .topic { cursor: pointer; }
            .topic:hover { opacity: 0.8; }
            #details { 
              background: white;
              padding: 20px;
              border-radius: 8px;
              box-shadow: 0 2px 4px rgba(0,0,0,0.1);
              margin-top: 20px;
            }
            .term { 
              display: inline-block; 
              margin: 5px; 
              padding: 5px 10px; 
              background: #e3f2fd; 
              border-radius: 3px;
              color: #1976d2;
              font-size: 14px;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <h1>Topic Analysis Results</h1>
            
            <div class="viz-panel">
              <h3>Topic Overview</h3>
              <div id="bubble-viz"></div>
            </div>

            <div id="details">Click on a topic to see details</div>
          </div>

          <script>
            const topicsData = #{topics_json};

            // Create bubble chart
            function createBubbleChart() {
              const width = document.getElementById('bubble-viz').clientWidth - 30;
              const height = 470;

              const svg = d3.select("#bubble-viz")
                .append("svg")
                .attr("width", width)
                .attr("height", height);

              // Create scale for bubble sizes
              const sizeScale = d3.scaleSqrt()
                .domain([0, d3.max(topicsData, d => d.size)])
                .range([20, 60]);

              // Create color scale
              const colorScale = d3.scaleSequential(d3.interpolateTurbo)
                .domain([0, 1]);

              // Create force simulation
              const simulation = d3.forceSimulation(topicsData)
                .force("x", d3.forceX(width / 2).strength(0.05))
                .force("y", d3.forceY(height / 2).strength(0.05))
                .force("collide", d3.forceCollide(d => sizeScale(d.size) + 3));

              // Create bubbles
              const bubbles = svg.selectAll(".topic")
                .data(topicsData)
                .enter().append("g")
                .attr("class", "topic");

              bubbles.append("circle")
                .attr("r", d => sizeScale(d.size))
                .attr("fill", d => colorScale(d.coherence))
                .attr("stroke", "#fff")
                .attr("stroke-width", 2)
                .style("filter", "drop-shadow(0px 2px 3px rgba(0,0,0,0.2))");

              bubbles.append("text")
                .text(d => d.label)
                .attr("text-anchor", "middle")
                .attr("dy", ".3em")
                .style("font-size", d => Math.min(sizeScale(d.size) / 3, 14) + "px")
                .style("fill", "white")
                .style("font-weight", "500");

              // Add click handler
              bubbles.on("click", function(event, d) {
                showDetails(d);
              });

              // Update positions
              simulation.on("tick", () => {
                bubbles.attr("transform", d => `translate(${d.x},${d.y})`);
              });
            }

            // Show topic details
            function showDetails(topic) {
              const details = document.getElementById('details');
              let summaryHtml = '';
              if (topic.summary) {
                summaryHtml = `
                  <p><strong>Summary:</strong></p>
                  <p style="font-size: 1.1em; color: #2c5234; padding: 15px; background: #e8f5e8; border-radius: 6px; border-left: 4px solid #4caf50; margin: 15px 0; line-height: 1.5;">${topic.summary}</p>
                `;
              }
              
              details.innerHTML = `
                <h2>${topic.label}</h2>
                <p><strong>Documents:</strong> ${topic.size}</p>
                <p><strong>Coherence:</strong> ${(topic.coherence * 100).toFixed(1)}%</p>
                ${summaryHtml}
                <p><strong>Top Terms:</strong></p>
                <div>${topic.terms.map(t => `<span class="term">${t}</span>`).join('')}</div>
                <p><strong>Sample Documents:</strong></p>
                ${topic.samples.map(s => `<p style="font-size: 0.9em; color: #666; padding: 10px; background: #f5f5f5; border-radius: 4px; margin: 10px 0;">"${s}..."</p>`).join('')}
              `;
            }

            // Initialize visualizations
            createBubbleChart();

            // Show first topic details by default
            if (topicsData.length > 0) {
              showDetails(topicsData[0]);
            }
          </script>
        </body>
        </html>
      HTML
    end

  end
end