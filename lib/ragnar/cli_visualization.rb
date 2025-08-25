# frozen_string_literal: true

module Ragnar
  module CLIVisualization
    def generate_topic_visualization_html(topics, embeddings: nil, cluster_ids: nil)
      # Convert topics to JSON for D3.js
      topics_json = topics.map do |topic|
        {
          id: topic.id,
          label: topic.label || "Topic #{topic.id}",
          size: topic.size,
          terms: topic.terms.first(10),
          coherence: topic.coherence,
          samples: topic.representative_docs(k: 2).map { |d| d[0..200] }
        }
      end.to_json

      # Process embeddings for scatter plot if available
      embeddings_json = "null"
      if embeddings && cluster_ids
        # If embeddings are still high dimensional, we need to reduce them to 2D for visualization
        embedding_dims = embeddings.first&.size || 0
        
        if embedding_dims > 2
          # Apply UMAP to reduce to 2D specifically for visualization
          puts "Reducing #{embedding_dims}D embeddings to 2D for visualization..."
          require 'clusterkit'
          
          umap = ClusterKit::Dimensionality::UMAP.new(
            n_components: 2,
            n_neighbors: [15, embeddings.size / 10].min,  # Adjust neighbors based on dataset size
            random_seed: 42
          )
          
          embeddings_2d = umap.fit_transform(embeddings)
          
          points = embeddings_2d.map.with_index do |emb, idx|
            {
              x: emb[0] || 0,
              y: emb[1] || 0,
              cluster: cluster_ids[idx] || -1
            }
          end
        else
          # Already 2D, use as-is
          points = embeddings.map.with_index do |emb, idx|
            {
              x: emb[0] || 0,
              y: emb[1] || 0,
              cluster: cluster_ids[idx] || -1
            }
          end
        end
        
        # For very large datasets, sample points to avoid browser performance issues
        if points.size > 10000
          puts "Sampling 10000 points from #{points.size} for visualization performance"
          sampled_indices = points.size.times.to_a.sample(10000)
          points = sampled_indices.map { |i| points[i] }
        end
        
        embeddings_json = points.to_json
      end

      # Generate color palette for clusters
      max_cluster_id = cluster_ids&.max || 0
      num_clusters = max_cluster_id + 2  # +1 for 0-indexed, +1 for outliers (-1)

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
            .viz-container {
              display: flex;
              gap: 20px;
              margin-bottom: 20px;
            }
            .viz-panel {
              background: white;
              border-radius: 8px;
              box-shadow: 0 2px 4px rgba(0,0,0,0.1);
              padding: 15px;
            }
            #bubble-viz {
              flex: 1;
              height: 500px;
            }
            #scatter-viz {
              flex: 1;
              height: 500px;
            }
            .topic { cursor: pointer; }
            .topic:hover { opacity: 0.8; }
            #details { 
              background: white;
              padding: 20px;
              border-radius: 8px;
              box-shadow: 0 2px 4px rgba(0,0,0,0.1);
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
            .tab-buttons {
              margin-bottom: 20px;
            }
            .tab-button {
              padding: 10px 20px;
              margin-right: 10px;
              background: white;
              border: 2px solid #ddd;
              border-radius: 4px;
              cursor: pointer;
              font-size: 14px;
              transition: all 0.3s;
            }
            .tab-button:hover {
              background: #f0f0f0;
            }
            .tab-button.active {
              background: #2196F3;
              color: white;
              border-color: #2196F3;
            }
            .tab-content {
              display: none;
            }
            .tab-content.active {
              display: block;
            }
            .legend {
              position: absolute;
              top: 10px;
              right: 10px;
              background: rgba(255,255,255,0.9);
              padding: 10px;
              border-radius: 4px;
              font-size: 12px;
            }
            .legend-item {
              margin: 5px 0;
            }
            .legend-color {
              display: inline-block;
              width: 12px;
              height: 12px;
              margin-right: 5px;
              border-radius: 2px;
            }
            canvas {
              border-radius: 4px;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <h1>Topic Analysis Results</h1>
            
            <div class="tab-buttons">
              <button class="tab-button active" onclick="showTab('bubbles')">Topic Bubbles</button>
              #{embeddings && cluster_ids ? '<button class="tab-button" onclick="showTab(\'scatter\')">Embedding Scatter Plot</button>' : ''}
            </div>

            <div id="bubbles-tab" class="tab-content active">
              <div class="viz-panel">
                <h3>Topic Overview</h3>
                <div id="bubble-viz"></div>
              </div>
            </div>

            #{embeddings && cluster_ids ? generate_scatter_tab(nil, embeddings.size) : ''}

            <div id="details">Click on a topic to see details</div>
          </div>

          <script>
            const topicsData = #{topics_json};
            const embeddingsData = #{embeddings_json};
            const numClusters = #{num_clusters};

            // Tab switching
            function showTab(tabName) {
              document.querySelectorAll('.tab-content').forEach(tab => {
                tab.classList.remove('active');
              });
              document.querySelectorAll('.tab-button').forEach(btn => {
                btn.classList.remove('active');
              });
              
              if (tabName === 'bubbles') {
                document.getElementById('bubbles-tab').classList.add('active');
                document.querySelector('.tab-button').classList.add('active');
              } else if (tabName === 'scatter' && embeddingsData) {
                document.getElementById('scatter-tab').classList.add('active');
                document.querySelectorAll('.tab-button')[1].classList.add('active');
              }
            }

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

            // Create scatter plot using canvas for performance
            function createScatterPlot() {
              if (!embeddingsData) return;

              const container = document.getElementById('scatter-viz');
              const width = container.clientWidth - 30;
              const height = 470;

              // Create canvas
              const canvas = document.createElement('canvas');
              canvas.width = width;
              canvas.height = height;
              container.appendChild(canvas);
              const ctx = canvas.getContext('2d');

              // Find data bounds
              const xExtent = d3.extent(embeddingsData, d => d.x);
              const yExtent = d3.extent(embeddingsData, d => d.y);
              
              console.log('X extent:', xExtent);
              console.log('Y extent:', yExtent);
              console.log('Sample points:', embeddingsData.slice(0, 5));

              // Just map the data directly to the canvas - no padding calculations
              // This will stretch the data to fill the entire available space
              const xScale = d3.scaleLinear()
                .domain(xExtent)
                .range([40, width - 40]);

              const yScale = d3.scaleLinear()
                .domain(yExtent)
                .range([height - 40, 40]);

              // Create color scale for clusters
              const colors = d3.scaleOrdinal(d3.schemeCategory10)
                .domain(d3.range(-1, numClusters));

              // Clear canvas with white background
              ctx.fillStyle = '#ffffff';
              ctx.fillRect(0, 0, width, height);
              
              // Draw grid lines for reference
              ctx.strokeStyle = '#f0f0f0';
              ctx.lineWidth = 1;
              
              // Vertical grid lines
              for (let i = 0; i <= 10; i++) {
                const x = (width - 80) * i / 10 + 40;
                ctx.beginPath();
                ctx.moveTo(x, 40);
                ctx.lineTo(x, height - 40);
                ctx.stroke();
              }
              
              // Horizontal grid lines
              for (let i = 0; i <= 10; i++) {
                const y = (height - 80) * i / 10 + 40;
                ctx.beginPath();
                ctx.moveTo(40, y);
                ctx.lineTo(width - 40, y);
                ctx.stroke();
              }

              // Group points by cluster for better rendering
              const clusteredPoints = {};
              const outliers = [];
              
              embeddingsData.forEach(point => {
                if (point.cluster === -1) {
                  outliers.push(point);
                } else {
                  if (!clusteredPoints[point.cluster]) {
                    clusteredPoints[point.cluster] = [];
                  }
                  clusteredPoints[point.cluster].push(point);
                }
              });
              
              // Draw outliers first (in background)
              ctx.globalAlpha = 0.3;
              outliers.forEach(point => {
                const x = xScale(point.x);
                const y = yScale(point.y);
                
                ctx.beginPath();
                ctx.arc(x, y, 1.5, 0, 2 * Math.PI);
                ctx.fillStyle = '#808080';
                ctx.fill();
              });
              
              // Draw clustered points
              ctx.globalAlpha = 0.7;
              Object.keys(clusteredPoints).forEach(clusterId => {
                const points = clusteredPoints[clusterId];
                const color = colors(parseInt(clusterId));
                
                points.forEach(point => {
                  const x = xScale(point.x);
                  const y = yScale(point.y);
                  
                  ctx.beginPath();
                  ctx.arc(x, y, 3, 0, 2 * Math.PI);
                  ctx.fillStyle = color;
                  ctx.fill();
                  
                  // Add a subtle border
                  ctx.strokeStyle = color;
                  ctx.lineWidth = 0.5;
                  ctx.stroke();
                });
              });

              // Add legend
              const legend = document.createElement('div');
              legend.className = 'legend';
              legend.innerHTML = '<strong>Clusters</strong><br>';
              
              topicsData.forEach(topic => {
                legend.innerHTML += `
                  <div class="legend-item">
                    <span class="legend-color" style="background: ${colors(topic.id)}"></span>
                    ${topic.label}
                  </div>
                `;
              });
              
              if (embeddingsData.some(d => d.cluster === -1)) {
                legend.innerHTML += `
                  <div class="legend-item">
                    <span class="legend-color" style="background: rgba(128,128,128,0.5)"></span>
                    Outliers
                  </div>
                `;
              }
              
              container.style.position = 'relative';
              container.appendChild(legend);
            }

            // Show topic details
            function showDetails(topic) {
              const details = document.getElementById('details');
              details.innerHTML = `
                <h2>${topic.label}</h2>
                <p><strong>Documents:</strong> ${topic.size}</p>
                <p><strong>Coherence:</strong> ${(topic.coherence * 100).toFixed(1)}%</p>
                <p><strong>Top Terms:</strong></p>
                <div>${topic.terms.map(t => `<span class="term">${t}</span>`).join('')}</div>
                <p><strong>Sample Documents:</strong></p>
                ${topic.samples.map(s => `<p style="font-size: 0.9em; color: #666; padding: 10px; background: #f5f5f5; border-radius: 4px; margin: 10px 0;">"${s}..."</p>`).join('')}
              `;
            }

            // Initialize visualizations
            createBubbleChart();
            if (embeddingsData) {
              setTimeout(() => createScatterPlot(), 100);  // Small delay to ensure DOM is ready
            }

            // Show first topic details by default
            if (topicsData.length > 0) {
              showDetails(topicsData[0]);
            }
          </script>
        </body>
        </html>
      HTML
    end

    private

    def generate_scatter_tab(point_count = nil, total_count = nil)
      sampling_message = if total_count && total_count > 10000
        "Showing 10,000 sampled points from #{total_count} total documents."
      else
        ""
      end
      
      <<~HTML
        <div id="scatter-tab" class="tab-content">
          <div class="viz-panel">
            <h3>Embedding Space Visualization</h3>
            <p style="color: #666; font-size: 14px; margin: 10px 0;">
              Each point represents a document, colored by its assigned topic cluster.
              #{sampling_message}
            </p>
            <div id="scatter-viz"></div>
          </div>
        </div>
      HTML
    end
  end
end