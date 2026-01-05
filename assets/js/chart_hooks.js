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

export default {
  PostsRateChart,
  LanguageChart,
  MediaChart,
  HourlyChart,
  HashtagsChart,
  LiveRateChart
}
