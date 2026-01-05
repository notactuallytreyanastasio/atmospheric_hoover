import * as d3 from "d3"

// Sexy animated area chart for posts per minute
const PostsRateChart = {
  mounted() {
    this.data = JSON.parse(this.el.dataset.points || "[]")
    this.svg = null
    this.render(true)
    this.handleEvent("update-posts-rate", ({points}) => {
      this.data = points
      this.update()
    })
  },
  render(animate = true) {
    const container = this.el
    container.innerHTML = ""

    const data = this.data.map((d, i) => ({
      index: i,
      count: parseInt(d.count) || 0
    }))

    if (data.length === 0) return

    const margin = {top: 20, right: 20, bottom: 30, left: 50}
    const width = container.clientWidth - margin.left - margin.right
    const height = 200 - margin.top - margin.bottom

    this.svg = d3.select(container)
      .append("svg")
      .attr("width", width + margin.left + margin.right)
      .attr("height", height + margin.top + margin.bottom)
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`)

    const svg = this.svg
    this.width = width
    this.height = height
    this.margin = margin

    // Gradient fill
    const defs = svg.append("defs")
    const gradient = defs.append("linearGradient")
      .attr("id", "areaGradient")
      .attr("x1", "0%").attr("y1", "0%")
      .attr("x2", "0%").attr("y2", "100%")
    gradient.append("stop")
      .attr("offset", "0%")
      .attr("stop-color", "#3b82f6")
      .attr("stop-opacity", 0.8)
    gradient.append("stop")
      .attr("offset", "100%")
      .attr("stop-color", "#3b82f6")
      .attr("stop-opacity", 0.1)

    this.x = d3.scaleLinear()
      .domain([0, data.length - 1])
      .range([0, width])

    const maxY = d3.max(data, d => d.count) || 1
    this.y = d3.scaleLinear()
      .domain([0, maxY * 1.1])
      .range([height, 0])

    // Area generator
    this.area = d3.area()
      .x(d => this.x(d.index))
      .y0(height)
      .y1(d => this.y(d.count))
      .curve(d3.curveMonotoneX)

    // Line generator
    this.line = d3.line()
      .x(d => this.x(d.index))
      .y(d => this.y(d.count))
      .curve(d3.curveMonotoneX)

    // Draw area
    svg.append("path")
      .datum(data)
      .attr("class", "area-path")
      .attr("fill", "url(#areaGradient)")
      .attr("d", this.area)

    // Draw line
    svg.append("path")
      .datum(data)
      .attr("class", "line-path")
      .attr("fill", "none")
      .attr("stroke", "#3b82f6")
      .attr("stroke-width", 2.5)
      .attr("d", this.line)

    // Dots
    svg.selectAll(".dot")
      .data(data)
      .enter().append("circle")
      .attr("class", "dot")
      .attr("cx", d => this.x(d.index))
      .attr("cy", d => this.y(d.count))
      .attr("r", 4)
      .attr("fill", "#3b82f6")
      .attr("stroke", "#fff")
      .attr("stroke-width", 2)

    // Y-axis
    this.yAxis = svg.append("g")
      .attr("class", "y-axis")
      .call(d3.axisLeft(this.y).ticks(5).tickFormat(d3.format(".0s")))

    svg.selectAll(".y-axis text").attr("fill", "#9ca3af").attr("font-size", "11px")
    svg.selectAll(".y-axis path, .y-axis line").attr("stroke", "#374151")
  },
  update() {
    if (!this.svg) {
      this.render(false)
      return
    }

    const data = this.data.map((d, i) => ({
      index: i,
      count: parseInt(d.count) || 0
    }))

    if (data.length === 0) return

    const maxY = d3.max(data, d => d.count) || 1
    this.y.domain([0, maxY * 1.1])

    // Update area with transition
    this.svg.select(".area-path")
      .datum(data)
      .transition()
      .duration(300)
      .attr("d", this.area)

    // Update line with transition
    this.svg.select(".line-path")
      .datum(data)
      .transition()
      .duration(300)
      .attr("d", this.line)

    // Update dots
    const dots = this.svg.selectAll(".dot").data(data)
    dots.transition()
      .duration(300)
      .attr("cx", d => this.x(d.index))
      .attr("cy", d => this.y(d.count))

    // Update y-axis
    this.yAxis.transition()
      .duration(300)
      .call(d3.axisLeft(this.y).ticks(5).tickFormat(d3.format(".0s")))

    this.svg.selectAll(".y-axis text").attr("fill", "#9ca3af").attr("font-size", "11px")
    this.svg.selectAll(".y-axis path, .y-axis line").attr("stroke", "#374151")
  }
}

// Horizontal bar chart for languages
const LanguageChart = {
  mounted() {
    this.data = JSON.parse(this.el.dataset.languages || "[]")
    this.render()
    this.handleEvent("update-languages", ({languages}) => {
      this.data = languages
      this.update()
    })
  },
  render() {
    const container = this.el
    container.innerHTML = ""

    const data = this.data.slice(0, 10).map(d => ({
      lang: d.lang || "?",
      count: parseInt(d.count) || 0
    }))

    if (data.length === 0) return

    const margin = {top: 10, right: 60, bottom: 10, left: 50}
    const width = container.clientWidth - margin.left - margin.right
    const barHeight = 28
    const height = data.length * barHeight

    this.svg = d3.select(container)
      .append("svg")
      .attr("width", width + margin.left + margin.right)
      .attr("height", height + margin.top + margin.bottom)
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`)

    const svg = this.svg
    this.width = width

    // Gradient
    const defs = svg.append("defs")
    const gradient = defs.append("linearGradient")
      .attr("id", "barGradient")
      .attr("x1", "0%").attr("y1", "0%")
      .attr("x2", "100%").attr("y2", "0%")
    gradient.append("stop")
      .attr("offset", "0%")
      .attr("stop-color", "#8b5cf6")
    gradient.append("stop")
      .attr("offset", "100%")
      .attr("stop-color", "#ec4899")

    this.x = d3.scaleLinear()
      .domain([0, d3.max(data, d => d.count) || 1])
      .range([0, width])

    this.y = d3.scaleBand()
      .domain(data.map(d => d.lang))
      .range([0, height])
      .padding(0.25)

    // Bars
    svg.selectAll(".bar")
      .data(data)
      .enter().append("rect")
      .attr("class", "bar")
      .attr("x", 0)
      .attr("y", d => this.y(d.lang))
      .attr("height", this.y.bandwidth())
      .attr("width", d => this.x(d.count))
      .attr("fill", "url(#barGradient)")
      .attr("rx", 4)

    // Labels on left
    svg.selectAll(".label")
      .data(data)
      .enter().append("text")
      .attr("class", "label")
      .attr("x", -8)
      .attr("y", d => this.y(d.lang) + this.y.bandwidth() / 2)
      .attr("dy", "0.35em")
      .attr("text-anchor", "end")
      .attr("fill", "#9ca3af")
      .attr("font-size", "13px")
      .attr("font-family", "monospace")
      .text(d => d.lang)

    // Count on right
    svg.selectAll(".count")
      .data(data)
      .enter().append("text")
      .attr("class", "count")
      .attr("x", d => this.x(d.count) + 8)
      .attr("y", d => this.y(d.lang) + this.y.bandwidth() / 2)
      .attr("dy", "0.35em")
      .attr("fill", "#d1d5db")
      .attr("font-size", "12px")
      .text(d => d3.format(",")(d.count))
  },
  update() {
    if (!this.svg) {
      this.render()
      return
    }

    const data = this.data.slice(0, 10).map(d => ({
      lang: d.lang || "?",
      count: parseInt(d.count) || 0
    }))

    this.x.domain([0, d3.max(data, d => d.count) || 1])

    // Update bars
    this.svg.selectAll(".bar")
      .data(data)
      .transition()
      .duration(300)
      .attr("width", d => this.x(d.count))

    // Update counts
    this.svg.selectAll(".count")
      .data(data)
      .transition()
      .duration(300)
      .attr("x", d => this.x(d.count) + 8)
      .text(d => d3.format(",")(d.count))
  }
}

// Donut chart for media types
const MediaChart = {
  mounted() {
    this.data = JSON.parse(this.el.dataset.stats || "{}")
    this.render()
    this.handleEvent("update-media", ({stats}) => {
      this.data = stats
      this.render() // Full re-render for donut is simpler
    })
  },
  render() {
    const container = this.el
    container.innerHTML = ""

    const stats = this.data
    if (!stats.images && !stats.videos && !stats.links) return

    const data = [
      { label: "Images", value: parseInt(stats.images) || 0, color: "#22c55e" },
      { label: "Videos", value: parseInt(stats.videos) || 0, color: "#ef4444" },
      { label: "Links", value: parseInt(stats.links) || 0, color: "#3b82f6" }
    ].filter(d => d.value > 0)

    const width = Math.min(container.clientWidth, 280)
    const height = 200
    const radius = Math.min(width, height) / 2 - 10
    const innerRadius = radius * 0.6

    const svg = d3.select(container)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .append("g")
      .attr("transform", `translate(${width/2},${height/2})`)

    const pie = d3.pie()
      .value(d => d.value)
      .sort(null)
      .padAngle(0.02)

    const arc = d3.arc()
      .innerRadius(innerRadius)
      .outerRadius(radius)
      .cornerRadius(4)

    const arcHover = d3.arc()
      .innerRadius(innerRadius)
      .outerRadius(radius + 8)
      .cornerRadius(4)

    const total = d3.sum(data, d => d.value)

    // Center text
    const centerText = svg.append("text")
      .attr("text-anchor", "middle")
      .attr("dy", "-0.3em")
      .attr("fill", "#9ca3af")
      .attr("font-size", "12px")
      .text("Total")

    const centerValue = svg.append("text")
      .attr("text-anchor", "middle")
      .attr("dy", "1em")
      .attr("fill", "#fff")
      .attr("font-size", "20px")
      .attr("font-weight", "bold")
      .text(d3.format(",")(total))

    const arcs = svg.selectAll(".arc")
      .data(pie(data))
      .enter().append("g")
      .attr("class", "arc")

    arcs.append("path")
      .attr("d", arc)
      .attr("fill", d => d.data.color)
      .attr("stroke", "#1f2937")
      .attr("stroke-width", 2)
      .style("cursor", "pointer")
      .on("mouseenter", function(event, d) {
        d3.select(this).transition().duration(200).attr("d", arcHover)
        centerText.text(d.data.label)
        centerValue.text(d3.format(",")(d.data.value))
      })
      .on("mouseleave", function() {
        d3.select(this).transition().duration(200).attr("d", arc)
        centerText.text("Total")
        centerValue.text(d3.format(",")(total))
      })

    // Legend
    const legend = svg.append("g")
      .attr("transform", `translate(${radius + 20}, ${-data.length * 12})`)

    data.forEach((d, i) => {
      const g = legend.append("g")
        .attr("transform", `translate(0, ${i * 24})`)
      g.append("circle").attr("r", 6).attr("fill", d.color)
      g.append("text")
        .attr("x", 12)
        .attr("dy", "0.35em")
        .attr("fill", "#d1d5db")
        .attr("font-size", "12px")
        .text(d.label)
    })
  }
}

// Hourly activity bar chart
const HourlyChart = {
  mounted() {
    this.data = JSON.parse(this.el.dataset.hours || "[]")
    this.render()
    this.handleEvent("update-hourly", ({hours}) => {
      this.data = hours
      this.update()
    })
  },
  render() {
    const container = this.el
    container.innerHTML = ""

    const data = this.data.map((d, i) => ({
      index: i,
      posts: parseInt(d.posts) || 0,
      users: parseInt(d.unique_users) || 0
    }))

    if (data.length === 0) return

    const margin = {top: 20, right: 20, bottom: 30, left: 40}
    const width = container.clientWidth - margin.left - margin.right
    const height = 180 - margin.top - margin.bottom

    this.svg = d3.select(container)
      .append("svg")
      .attr("width", width + margin.left + margin.right)
      .attr("height", height + margin.top + margin.bottom)
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`)

    const svg = this.svg
    this.height = height

    this.x = d3.scaleBand()
      .domain(data.map(d => d.index))
      .range([0, width])
      .padding(0.1)

    const maxPosts = d3.max(data, d => d.posts) || 1
    this.y = d3.scaleLinear()
      .domain([0, maxPosts * 1.1])
      .range([height, 0])

    // Color scale
    this.colorScale = d3.scaleLinear()
      .domain([0, maxPosts])
      .range(["#065f46", "#10b981"])

    // Bars
    svg.selectAll(".bar")
      .data(data)
      .enter().append("rect")
      .attr("class", "bar")
      .attr("x", d => this.x(d.index))
      .attr("y", d => this.y(d.posts))
      .attr("width", this.x.bandwidth())
      .attr("height", d => height - this.y(d.posts))
      .attr("fill", d => this.colorScale(d.posts))
      .attr("rx", 2)

    // Y-axis
    this.yAxis = svg.append("g")
      .attr("class", "y-axis")
      .call(d3.axisLeft(this.y).ticks(4).tickFormat(d3.format(".0s")))

    svg.selectAll(".y-axis text").attr("fill", "#9ca3af").attr("font-size", "10px")
    svg.selectAll(".y-axis path, .y-axis line").attr("stroke", "#374151")
  },
  update() {
    if (!this.svg) {
      this.render()
      return
    }

    const data = this.data.map((d, i) => ({
      index: i,
      posts: parseInt(d.posts) || 0,
      users: parseInt(d.unique_users) || 0
    }))

    const maxPosts = d3.max(data, d => d.posts) || 1
    this.y.domain([0, maxPosts * 1.1])
    this.colorScale.domain([0, maxPosts])

    // Update bars
    this.svg.selectAll(".bar")
      .data(data)
      .transition()
      .duration(300)
      .attr("y", d => this.y(d.posts))
      .attr("height", d => this.height - this.y(d.posts))
      .attr("fill", d => this.colorScale(d.posts))

    // Update y-axis
    this.yAxis.transition()
      .duration(300)
      .call(d3.axisLeft(this.y).ticks(4).tickFormat(d3.format(".0s")))

    this.svg.selectAll(".y-axis text").attr("fill", "#9ca3af").attr("font-size", "10px")
    this.svg.selectAll(".y-axis path, .y-axis line").attr("stroke", "#374151")
  }
}

// Trending hashtags list
const HashtagsChart = {
  mounted() {
    this.data = JSON.parse(this.el.dataset.hashtags || "[]")
    this.render()
    this.handleEvent("update-hashtags", ({hashtags}) => {
      this.data = hashtags
      this.render() // Simple re-render for list
    })
  },
  render() {
    const container = this.el
    container.innerHTML = ""

    const data = this.data.slice(0, 15)
    if (data.length === 0) {
      container.innerHTML = '<div class="text-gray-500 text-sm py-4">No hashtags in the last hour</div>'
      return
    }

    const maxCount = d3.max(data, d => parseInt(d.count) || 1)

    const list = d3.select(container)
      .append("div")
      .attr("class", "space-y-1")

    const items = list.selectAll(".hashtag-item")
      .data(data)
      .enter()
      .append("div")
      .attr("class", "hashtag-item flex items-center gap-2 py-1.5 px-2 rounded hover:bg-gray-800/50 transition-colors")

    items.append("span")
      .attr("class", "w-5 text-xs text-gray-500 font-mono")
      .text((d, i) => `${i + 1}.`)

    items.append("span")
      .attr("class", "flex-1 text-sm text-blue-400 font-medium truncate")
      .text(d => `#${d.hashtag}`)

    items.append("div")
      .attr("class", "w-16 h-1.5 bg-gray-700 rounded overflow-hidden")
      .append("div")
      .attr("class", "h-full bg-gradient-to-r from-blue-500 to-cyan-400 rounded")
      .style("width", d => `${(parseInt(d.count) / maxCount) * 100}%`)

    items.append("span")
      .attr("class", "w-10 text-right text-xs text-gray-400 font-mono")
      .text(d => d3.format(",")(parseInt(d.count)))
  }
}

// Live posts per minute chart (real-time from firehose)
const LiveRateChart = {
  mounted() {
    this.data = []
    this.svg = null
    this.render()
    this.handleEvent("update-live-rate", ({points}) => {
      this.data = points
      this.update()
    })
  },
  render() {
    const container = this.el
    container.innerHTML = ""

    const data = this.data.map((d, i) => ({
      index: i,
      count: parseInt(d.count) || 0
    }))

    const margin = {top: 20, right: 20, bottom: 30, left: 50}
    const width = container.clientWidth - margin.left - margin.right
    const height = 220 - margin.top - margin.bottom

    const svgEl = d3.select(container)
      .append("svg")
      .attr("width", width + margin.left + margin.right)
      .attr("height", height + margin.top + margin.bottom)

    this.svg = svgEl.append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`)

    const svg = this.svg
    this.width = width
    this.height = height

    // Gradient fill
    const defs = svgEl.append("defs")
    const gradient = defs.append("linearGradient")
      .attr("id", "liveAreaGradient")
      .attr("x1", "0%").attr("y1", "0%")
      .attr("x2", "0%").attr("y2", "100%")
    gradient.append("stop")
      .attr("offset", "0%")
      .attr("stop-color", "#10b981")
      .attr("stop-opacity", 0.8)
    gradient.append("stop")
      .attr("offset", "100%")
      .attr("stop-color", "#10b981")
      .attr("stop-opacity", 0.1)

    // Glow effect
    const glow = defs.append("filter")
      .attr("id", "glow")
    glow.append("feGaussianBlur")
      .attr("stdDeviation", "2")
      .attr("result", "coloredBlur")
    const feMerge = glow.append("feMerge")
    feMerge.append("feMergeNode").attr("in", "coloredBlur")
    feMerge.append("feMergeNode").attr("in", "SourceGraphic")

    this.x = d3.scaleLinear()
      .domain([0, 29])
      .range([0, width])

    const maxY = Math.max(d3.max(data, d => d.count) || 1, 10)
    this.y = d3.scaleLinear()
      .domain([0, maxY * 1.1])
      .range([height, 0])

    // Area generator
    this.area = d3.area()
      .x(d => this.x(d.index))
      .y0(height)
      .y1(d => this.y(d.count))
      .curve(d3.curveMonotoneX)

    // Line generator
    this.line = d3.line()
      .x(d => this.x(d.index))
      .y(d => this.y(d.count))
      .curve(d3.curveMonotoneX)

    // Draw area
    svg.append("path")
      .datum(data)
      .attr("class", "area-path")
      .attr("fill", "url(#liveAreaGradient)")
      .attr("d", this.area)

    // Draw line with glow
    svg.append("path")
      .datum(data)
      .attr("class", "line-path")
      .attr("fill", "none")
      .attr("stroke", "#10b981")
      .attr("stroke-width", 3)
      .attr("filter", "url(#glow)")
      .attr("d", this.line)

    // Dots
    svg.selectAll(".dot")
      .data(data)
      .enter().append("circle")
      .attr("class", "dot")
      .attr("cx", d => this.x(d.index))
      .attr("cy", d => this.y(d.count))
      .attr("r", 4)
      .attr("fill", "#10b981")
      .attr("stroke", "#fff")
      .attr("stroke-width", 2)

    // Highlight current minute (last dot)
    svg.append("circle")
      .attr("class", "current-dot")
      .attr("cx", this.x(29))
      .attr("cy", data.length > 0 ? this.y(data[29]?.count || 0) : height)
      .attr("r", 6)
      .attr("fill", "#34d399")
      .attr("stroke", "#fff")
      .attr("stroke-width", 2)
      .attr("filter", "url(#glow)")

    // Y-axis
    this.yAxis = svg.append("g")
      .attr("class", "y-axis")
      .call(d3.axisLeft(this.y).ticks(5).tickFormat(d3.format(".0s")))

    svg.selectAll(".y-axis text").attr("fill", "#9ca3af").attr("font-size", "11px")
    svg.selectAll(".y-axis path, .y-axis line").attr("stroke", "#374151")

    // X-axis labels
    svg.append("text")
      .attr("x", 0)
      .attr("y", height + 20)
      .attr("fill", "#6b7280")
      .attr("font-size", "11px")
      .text("30 min ago")

    svg.append("text")
      .attr("x", width)
      .attr("y", height + 20)
      .attr("fill", "#6b7280")
      .attr("font-size", "11px")
      .attr("text-anchor", "end")
      .text("now")

    // Current count label
    this.countLabel = svg.append("text")
      .attr("class", "count-label")
      .attr("x", width - 5)
      .attr("y", 0)
      .attr("fill", "#10b981")
      .attr("font-size", "14px")
      .attr("font-weight", "bold")
      .attr("text-anchor", "end")
      .text(data.length > 0 ? `${d3.format(",")(data[29]?.count || 0)} this min` : "")
  },
  update() {
    if (!this.svg) {
      this.render()
      return
    }

    const data = this.data.map((d, i) => ({
      index: i,
      count: parseInt(d.count) || 0
    }))

    if (data.length === 0) return

    const maxY = Math.max(d3.max(data, d => d.count) || 1, 10)
    this.y.domain([0, maxY * 1.1])

    // Update area with transition
    this.svg.select(".area-path")
      .datum(data)
      .transition()
      .duration(200)
      .attr("d", this.area)

    // Update line with transition
    this.svg.select(".line-path")
      .datum(data)
      .transition()
      .duration(200)
      .attr("d", this.line)

    // Update dots
    const dots = this.svg.selectAll(".dot").data(data)
    dots.transition()
      .duration(200)
      .attr("cx", d => this.x(d.index))
      .attr("cy", d => this.y(d.count))

    // Update current minute highlight
    this.svg.select(".current-dot")
      .transition()
      .duration(200)
      .attr("cy", this.y(data[29]?.count || 0))

    // Update y-axis
    this.yAxis.transition()
      .duration(200)
      .call(d3.axisLeft(this.y).ticks(5).tickFormat(d3.format(".0s")))

    this.svg.selectAll(".y-axis text").attr("fill", "#9ca3af").attr("font-size", "11px")
    this.svg.selectAll(".y-axis path, .y-axis line").attr("stroke", "#374151")

    // Update count label
    this.svg.select(".count-label")
      .text(`${d3.format(",")(data[29]?.count || 0)} this min`)
  }
}

// Thread velocity chart (replies per minute)
const ThreadVelocityChart = {
  mounted() {
    this.data = JSON.parse(this.el.dataset.points || "[]")
    this.svg = null
    this.render()
    this.handleEvent("update-thread-velocity", ({points}) => {
      this.data = points
      this.update()
    })
  },
  render() {
    const container = this.el
    container.innerHTML = ""

    const data = this.data.map((d, i) => ({
      index: i,
      count: parseInt(d.replies) || 0
    }))

    if (data.length === 0) {
      container.innerHTML = '<div class="text-gray-500 text-sm py-8 text-center">No velocity data yet</div>'
      return
    }

    const margin = {top: 10, right: 20, bottom: 20, left: 40}
    const width = container.clientWidth - margin.left - margin.right
    const height = 100 - margin.top - margin.bottom

    const svgEl = d3.select(container)
      .append("svg")
      .attr("width", width + margin.left + margin.right)
      .attr("height", height + margin.top + margin.bottom)

    this.svg = svgEl.append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`)

    const svg = this.svg
    this.width = width
    this.height = height

    // Gradient
    const defs = svgEl.append("defs")
    const gradient = defs.append("linearGradient")
      .attr("id", "velocityGradient")
      .attr("x1", "0%").attr("y1", "0%")
      .attr("x2", "0%").attr("y2", "100%")
    gradient.append("stop")
      .attr("offset", "0%")
      .attr("stop-color", "#f97316")
      .attr("stop-opacity", 0.8)
    gradient.append("stop")
      .attr("offset", "100%")
      .attr("stop-color", "#f97316")
      .attr("stop-opacity", 0.1)

    this.x = d3.scaleLinear()
      .domain([0, data.length - 1])
      .range([0, width])

    const maxY = Math.max(d3.max(data, d => d.count) || 1, 5)
    this.y = d3.scaleLinear()
      .domain([0, maxY * 1.1])
      .range([height, 0])

    // Area
    this.area = d3.area()
      .x(d => this.x(d.index))
      .y0(height)
      .y1(d => this.y(d.count))
      .curve(d3.curveMonotoneX)

    // Line
    this.line = d3.line()
      .x(d => this.x(d.index))
      .y(d => this.y(d.count))
      .curve(d3.curveMonotoneX)

    svg.append("path")
      .datum(data)
      .attr("class", "area-path")
      .attr("fill", "url(#velocityGradient)")
      .attr("d", this.area)

    svg.append("path")
      .datum(data)
      .attr("class", "line-path")
      .attr("fill", "none")
      .attr("stroke", "#f97316")
      .attr("stroke-width", 2)
      .attr("d", this.line)

    // Y-axis
    this.yAxis = svg.append("g")
      .attr("class", "y-axis")
      .call(d3.axisLeft(this.y).ticks(3).tickFormat(d3.format("d")))

    svg.selectAll(".y-axis text").attr("fill", "#9ca3af").attr("font-size", "10px")
    svg.selectAll(".y-axis path, .y-axis line").attr("stroke", "#374151")
  },
  update() {
    if (!this.svg) {
      this.render()
      return
    }

    const data = this.data.map((d, i) => ({
      index: i,
      count: parseInt(d.replies) || 0
    }))

    if (data.length === 0) return

    this.x.domain([0, data.length - 1])
    const maxY = Math.max(d3.max(data, d => d.count) || 1, 5)
    this.y.domain([0, maxY * 1.1])

    this.svg.select(".area-path")
      .datum(data)
      .transition()
      .duration(300)
      .attr("d", this.area)

    this.svg.select(".line-path")
      .datum(data)
      .transition()
      .duration(300)
      .attr("d", this.line)

    this.yAxis.transition()
      .duration(300)
      .call(d3.axisLeft(this.y).ticks(3).tickFormat(d3.format("d")))

    this.svg.selectAll(".y-axis text").attr("fill", "#9ca3af").attr("font-size", "10px")
    this.svg.selectAll(".y-axis path, .y-axis line").attr("stroke", "#374151")
  }
}

// Thread tree visualization (hierarchical reply structure)
const ThreadTreeChart = {
  mounted() {
    this.data = JSON.parse(this.el.dataset.posts || "null")
    this.currentPath = []
    this.currentIndex = 0
    this.isPlaying = false
    this.playInterval = null
    this.playSpeed = 2000 // ms per node
    this.render()
    this.handleEvent("render-thread-tree", ({posts}) => {
      this.data = posts
      this.stopPlayback()
      this.render()
    })
  },
  destroyed() {
    this.stopPlayback()
  },
  stopPlayback() {
    this.isPlaying = false
    if (this.playInterval) {
      clearInterval(this.playInterval)
      this.playInterval = null
    }
  },
  // Get all paths from root to leaves
  getAllPaths(node, currentPath = []) {
    const newPath = [...currentPath, node]
    if (!node.children || node.children.length === 0) {
      return [newPath]
    }
    return node.children.flatMap(child => this.getAllPaths(child, newPath))
  },
  // Get the longest/deepest path
  getLongestPath(root) {
    const paths = this.getAllPaths(root)
    return paths.reduce((longest, path) => path.length > longest.length ? path : longest, [])
  },
  render() {
    const container = this.el
    container.innerHTML = ""

    if (!this.data) {
      container.innerHTML = '<div class="text-gray-500 text-sm py-8 text-center">No tree data available</div>'
      return
    }

    const root = d3.hierarchy(this.data, d => d.children)
    this.root = root
    const nodeCount = root.descendants().length

    // Initialize with longest path
    this.currentPath = this.getLongestPath(root)
    this.currentIndex = 0
    this.allPaths = this.getAllPaths(root)

    // Card-style node dimensions
    const cardWidth = 280
    const cardHeight = 80
    const nodeSpacingY = 100
    const nodeSpacingX = 320
    const margin = {top: 40, right: 40, bottom: 40, left: 40}

    // Use tree layout with card-sized spacing
    const treeLayout = d3.tree()
      .nodeSize([nodeSpacingY, nodeSpacingX])
      .separation((a, b) => a.parent === b.parent ? 1 : 1.2)

    treeLayout(root)

    // Calculate bounds
    let x0 = Infinity, x1 = -Infinity
    let y0 = Infinity, y1 = -Infinity
    root.each(d => {
      if (d.x > x1) x1 = d.x
      if (d.x < x0) x0 = d.x
      if (d.y > y1) y1 = d.y
      if (d.y < y0) y0 = d.y
    })

    const treeHeight = x1 - x0 + cardHeight
    const treeWidth = y1 - y0 + cardWidth
    const svgHeight = treeHeight + margin.top + margin.bottom
    const svgWidth = Math.max(container.clientWidth, treeWidth + margin.left + margin.right)

    // Navigator controls
    const controls = d3.select(container)
      .append("div")
      .attr("class", "navigator-controls")
      .style("display", "flex")
      .style("align-items", "center")
      .style("gap", "12px")
      .style("padding", "12px 16px")
      .style("background", "#ffffff")
      .style("border-bottom", "1px solid #e2e8f0")
      .style("border-radius", "12px 12px 0 0")

    // Play/Pause button
    const playBtn = controls.append("button")
      .attr("class", "nav-play-btn")
      .style("display", "flex")
      .style("align-items", "center")
      .style("justify-content", "center")
      .style("width", "40px")
      .style("height", "40px")
      .style("border-radius", "50%")
      .style("background", "#3b82f6")
      .style("border", "none")
      .style("cursor", "pointer")
      .style("color", "#ffffff")
      .style("font-size", "18px")
      .html("▶")
      .on("click", () => this.togglePlayback(playBtn, wrapper))

    // Prev button
    controls.append("button")
      .style("padding", "8px 12px")
      .style("border-radius", "8px")
      .style("background", "#f1f5f9")
      .style("border", "1px solid #e2e8f0")
      .style("cursor", "pointer")
      .style("font-size", "14px")
      .text("← Prev")
      .on("click", () => this.navigatePrev(wrapper))

    // Next button
    controls.append("button")
      .style("padding", "8px 12px")
      .style("border-radius", "8px")
      .style("background", "#f1f5f9")
      .style("border", "1px solid #e2e8f0")
      .style("cursor", "pointer")
      .style("font-size", "14px")
      .text("Next →")
      .on("click", () => this.navigateNext(wrapper))

    // Position indicator
    this.positionLabel = controls.append("span")
      .style("padding", "6px 12px")
      .style("background", "#f8fafc")
      .style("border-radius", "16px")
      .style("font-size", "13px")
      .style("color", "#64748b")
      .style("font-weight", "500")
      .text(`1 / ${this.currentPath.length}`)

    // Divider
    controls.append("div")
      .style("width", "1px")
      .style("height", "24px")
      .style("background", "#e2e8f0")

    // Path selector
    controls.append("span")
      .style("font-size", "13px")
      .style("color", "#64748b")
      .text("Thread:")

    const pathSelect = controls.append("select")
      .style("padding", "6px 10px")
      .style("border-radius", "8px")
      .style("border", "1px solid #e2e8f0")
      .style("background", "#ffffff")
      .style("font-size", "13px")
      .style("cursor", "pointer")
      .on("change", (e) => this.selectPath(parseInt(e.target.value), wrapper))

    // Add path options (sorted by length, longest first)
    const sortedPaths = this.allPaths
      .map((p, i) => ({ path: p, index: i }))
      .sort((a, b) => b.path.length - a.path.length)

    sortedPaths.forEach((item, displayIdx) => {
      const lastNode = item.path[item.path.length - 1]
      const preview = (lastNode.data.text || "").slice(0, 30)
      pathSelect.append("option")
        .attr("value", item.index)
        .attr("selected", displayIdx === 0 ? true : null)
        .text(`${item.path.length} posts: "${preview}..."`)
    })

    // Speed control
    controls.append("span")
      .style("font-size", "13px")
      .style("color", "#64748b")
      .style("margin-left", "8px")
      .text("Speed:")

    controls.append("select")
      .style("padding", "6px 10px")
      .style("border-radius", "8px")
      .style("border", "1px solid #e2e8f0")
      .style("background", "#ffffff")
      .style("font-size", "13px")
      .on("change", (e) => {
        this.playSpeed = parseInt(e.target.value)
        if (this.isPlaying) {
          this.stopPlayback()
          this.togglePlayback(playBtn, wrapper)
        }
      })
      .selectAll("option")
      .data([
        { value: 1000, label: "Fast (1s)" },
        { value: 2000, label: "Normal (2s)" },
        { value: 3000, label: "Slow (3s)" },
        { value: 5000, label: "Very Slow (5s)" }
      ])
      .join("option")
      .attr("value", d => d.value)
      .attr("selected", d => d.value === 2000 ? true : null)
      .text(d => d.label)

    // Create scrollable wrapper
    const wrapper = d3.select(container)
      .append("div")
      .attr("class", "tree-wrapper")
      .style("width", "100%")
      .style("height", "450px")
      .style("overflow", "auto")
      .style("background", "linear-gradient(135deg, #f8fafc 0%, #f1f5f9 100%)")
      .style("border-radius", "0 0 12px 12px")

    this.wrapper = wrapper

    const svg = wrapper
      .append("svg")
      .attr("width", svgWidth)
      .attr("height", svgHeight)
      .style("font", "13px -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif")

    this.svg = svg

    const g = svg.append("g")
      .attr("transform", `translate(${margin.left - y0 + cardWidth/2}, ${margin.top - x0 + cardHeight/2})`)

    this.g = g
    this.cardWidth = cardWidth
    this.cardHeight = cardHeight
    this.margin = margin
    this.x0 = x0
    this.y0 = y0

    // Gradient definitions
    const defs = svg.append("defs")

    // Drop shadow filter
    const dropShadow = defs.append("filter")
      .attr("id", "cardShadow")
      .attr("x", "-20%")
      .attr("y", "-20%")
      .attr("width", "140%")
      .attr("height", "140%")
    dropShadow.append("feDropShadow")
      .attr("dx", "0")
      .attr("dy", "2")
      .attr("stdDeviation", "4")
      .attr("flood-color", "rgba(0,0,0,0.1)")

    // Root glow filter
    const rootGlow = defs.append("filter")
      .attr("id", "rootGlow")
      .attr("x", "-50%")
      .attr("y", "-50%")
      .attr("width", "200%")
      .attr("height", "200%")
    rootGlow.append("feDropShadow")
      .attr("dx", "0")
      .attr("dy", "0")
      .attr("stdDeviation", "6")
      .attr("flood-color", "#f97316")
      .attr("flood-opacity", "0.4")

    // Active node glow
    const activeGlow = defs.append("filter")
      .attr("id", "activeGlow")
      .attr("x", "-50%")
      .attr("y", "-50%")
      .attr("width", "200%")
      .attr("height", "200%")
    activeGlow.append("feDropShadow")
      .attr("dx", "0")
      .attr("dy", "0")
      .attr("stdDeviation", "8")
      .attr("flood-color", "#3b82f6")
      .attr("flood-opacity", "0.6")

    // Draw links
    g.append("g")
      .attr("class", "links")
      .attr("fill", "none")
      .attr("stroke", "#cbd5e1")
      .attr("stroke-width", 2)
      .selectAll("path")
      .data(root.links())
      .join("path")
      .attr("class", "link")
      .attr("d", d3.linkHorizontal()
        .x(d => d.y)
        .y(d => d.x))

    // Nodes
    const node = g.append("g")
      .attr("class", "nodes")
      .selectAll("g")
      .data(root.descendants())
      .join("g")
      .attr("class", "node")
      .attr("data-id", d => d.data.uri)
      .attr("transform", d => `translate(${d.y},${d.x})`)
      .style("cursor", "pointer")
      .on("click", (e, d) => this.startFromNode(d, wrapper))

    // Card backgrounds
    node.append("rect")
      .attr("class", "card-bg")
      .attr("x", -cardWidth/2)
      .attr("y", -cardHeight/2)
      .attr("width", cardWidth)
      .attr("height", cardHeight)
      .attr("rx", 12)
      .attr("ry", 12)
      .attr("fill", "#ffffff")
      .attr("stroke", d => d.depth === 0 ? "#f97316" : "#e2e8f0")
      .attr("stroke-width", d => d.depth === 0 ? 2 : 1)
      .attr("filter", d => d.depth === 0 ? "url(#rootGlow)" : "url(#cardShadow)")

    // Avatar circle
    node.append("circle")
      .attr("cx", -cardWidth/2 + 28)
      .attr("cy", 0)
      .attr("r", 18)
      .attr("fill", d => {
        if (d.depth === 0) return "#f97316"
        if (d.data.has_images) return "#22c55e"
        if (d.data.has_video) return "#ef4444"
        return "#3b82f6"
      })

    // Avatar initial
    node.append("text")
      .attr("x", -cardWidth/2 + 28)
      .attr("y", 1)
      .attr("text-anchor", "middle")
      .attr("dominant-baseline", "middle")
      .attr("fill", "#ffffff")
      .attr("font-size", "14px")
      .attr("font-weight", "600")
      .text(d => (d.data.did || "").slice(-2).toUpperCase())

    // DID as handle
    node.append("text")
      .attr("x", -cardWidth/2 + 54)
      .attr("y", -12)
      .attr("fill", "#64748b")
      .attr("font-size", "11px")
      .text(d => {
        const did = d.data.did || ""
        return did.length > 32 ? did.slice(0, 16) + "..." + did.slice(-8) : did
      })

    // Post text
    node.each(function(d) {
      const text = d.data.text || ""
      const truncated = text.length > 80 ? text.slice(0, 80) + "..." : text
      const lines = []
      let current = ""

      truncated.split(" ").forEach(word => {
        if ((current + " " + word).length > 38) {
          lines.push(current.trim())
          current = word
        } else {
          current += " " + word
        }
      })
      if (current.trim()) lines.push(current.trim())

      const lineGroup = d3.select(this)
      lines.slice(0, 2).forEach((line, i) => {
        lineGroup.append("text")
          .attr("class", "post-text")
          .attr("x", -cardWidth/2 + 54)
          .attr("y", 8 + i * 16)
          .attr("fill", "#1e293b")
          .attr("font-size", "12px")
          .text(line)
      })
    })

    // Reply count badge
    node.filter(d => d.children && d.children.length > 0)
      .append("g")
      .attr("transform", `translate(${cardWidth/2 - 8}, ${-cardHeight/2 - 8})`)
      .call(g => {
        g.append("circle")
          .attr("r", 14)
          .attr("fill", "#3b82f6")
        g.append("text")
          .attr("text-anchor", "middle")
          .attr("dominant-baseline", "middle")
          .attr("fill", "#ffffff")
          .attr("font-size", "10px")
          .attr("font-weight", "600")
          .text(d => d.children.length)
      })

    // Root badge
    node.filter(d => d.depth === 0)
      .append("g")
      .attr("transform", `translate(${-cardWidth/2 + 28}, ${-cardHeight/2 - 12})`)
      .call(g => {
        g.append("rect")
          .attr("x", -20)
          .attr("y", -8)
          .attr("width", 40)
          .attr("height", 16)
          .attr("rx", 8)
          .attr("fill", "#f97316")
        g.append("text")
          .attr("text-anchor", "middle")
          .attr("dominant-baseline", "middle")
          .attr("fill", "#ffffff")
          .attr("font-size", "9px")
          .attr("font-weight", "600")
          .text("ROOT")
      })

    // Highlight first node and scroll to it
    setTimeout(() => {
      this.highlightCurrentNode()
      this.scrollToNode(this.currentPath[0])
    }, 100)
  },
  togglePlayback(btn, wrapper) {
    if (this.isPlaying) {
      this.stopPlayback()
      btn.html("▶")
    } else {
      this.isPlaying = true
      btn.html("⏸")
      this.playInterval = setInterval(() => {
        if (this.currentIndex < this.currentPath.length - 1) {
          this.navigateNext(wrapper)
        } else {
          // Loop back to start
          this.currentIndex = 0
          this.highlightCurrentNode()
          this.scrollToNode(this.currentPath[0])
          this.updatePositionLabel()
        }
      }, this.playSpeed)
    }
  },
  navigateNext(wrapper) {
    if (this.currentIndex < this.currentPath.length - 1) {
      this.currentIndex++
      this.highlightCurrentNode()
      this.scrollToNode(this.currentPath[this.currentIndex])
      this.updatePositionLabel()
    }
  },
  navigatePrev(wrapper) {
    if (this.currentIndex > 0) {
      this.currentIndex--
      this.highlightCurrentNode()
      this.scrollToNode(this.currentPath[this.currentIndex])
      this.updatePositionLabel()
    }
  },
  selectPath(pathIndex, wrapper) {
    this.stopPlayback()
    this.currentPath = this.allPaths[pathIndex]
    this.currentIndex = 0
    this.highlightCurrentNode()
    this.scrollToNode(this.currentPath[0])
    this.updatePositionLabel()
    // Update play button
    const btn = d3.select(this.el).select(".nav-play-btn")
    btn.html("▶")
  },
  startFromNode(node, wrapper) {
    // Find a path that includes this node and follow it from here
    const pathWithNode = this.allPaths.find(path =>
      path.some(n => n.data.uri === node.data.uri)
    )
    if (pathWithNode) {
      this.stopPlayback()
      this.currentPath = pathWithNode
      this.currentIndex = pathWithNode.findIndex(n => n.data.uri === node.data.uri)
      this.highlightCurrentNode()
      this.scrollToNode(node)
      this.updatePositionLabel()
      const btn = d3.select(this.el).select(".nav-play-btn")
      btn.html("▶")
    }
  },
  highlightCurrentNode() {
    const currentNode = this.currentPath[this.currentIndex]
    if (!currentNode || !this.g) return

    // Reset all nodes
    this.g.selectAll(".node .card-bg")
      .attr("stroke", d => d.depth === 0 ? "#f97316" : "#e2e8f0")
      .attr("stroke-width", d => d.depth === 0 ? 2 : 1)
      .attr("filter", d => d.depth === 0 ? "url(#rootGlow)" : "url(#cardShadow)")

    // Reset all links
    this.g.selectAll(".link")
      .attr("stroke", "#cbd5e1")
      .attr("stroke-width", 2)

    // Highlight path links
    const pathUris = new Set(this.currentPath.map(n => n.data.uri))
    this.g.selectAll(".link")
      .attr("stroke", d => {
        if (pathUris.has(d.source.data.uri) && pathUris.has(d.target.data.uri)) {
          return "#3b82f6"
        }
        return "#cbd5e1"
      })
      .attr("stroke-width", d => {
        if (pathUris.has(d.source.data.uri) && pathUris.has(d.target.data.uri)) {
          return 3
        }
        return 2
      })

    // Highlight current node
    this.g.selectAll(".node")
      .filter(d => d.data.uri === currentNode.data.uri)
      .select(".card-bg")
      .attr("stroke", "#3b82f6")
      .attr("stroke-width", 3)
      .attr("filter", "url(#activeGlow)")
  },
  scrollToNode(node) {
    if (!node || !this.wrapper) return

    const wrapperEl = this.wrapper.node()
    const cardWidth = this.cardWidth
    const cardHeight = this.cardHeight
    const margin = this.margin

    // Calculate node position in SVG coordinates
    const nodeX = margin.left - this.y0 + cardWidth/2 + node.y
    const nodeY = margin.top - this.x0 + cardHeight/2 + node.x

    // Scroll to center the node
    const scrollX = Math.max(0, nodeX - wrapperEl.clientWidth / 2)
    const scrollY = Math.max(0, nodeY - wrapperEl.clientHeight / 2)

    wrapperEl.scrollTo({ left: scrollX, top: scrollY, behavior: 'smooth' })
  },
  updatePositionLabel() {
    if (this.positionLabel) {
      this.positionLabel.text(`${this.currentIndex + 1} / ${this.currentPath.length}`)
    }
  }
}

export default {
  PostsRateChart,
  LanguageChart,
  MediaChart,
  HourlyChart,
  HashtagsChart,
  LiveRateChart,
  ThreadVelocityChart,
  ThreadTreeChart
}
