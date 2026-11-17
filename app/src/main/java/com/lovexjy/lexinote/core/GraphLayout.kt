package com.lovexjy.lexinote.core

import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

data class GraphData(
    var nodes: MutableList<GraphNode> = mutableListOf(),
    var edges: MutableList<GraphEdge> = mutableListOf()
)

private class LexiGraphForceVector(
    var x: Double = 0.0,
    var y: Double = 0.0
)

/**
 * Pure deterministic layout shared by GraphLayout.
 * Exact 1:1 port of LexiGraphForce.ets.
 */
object LexiGraphForce {
    fun golden(nodes: List<GraphNode>) {
        val count = nodes.size
        val goldenAngle = Math.PI * (3.0 - sqrt(5.0))
        for (index in 0 until count) {
            val radius = if (count == 1) 0.0 else sqrt((index + 0.5) / count) * 0.42
            nodes[index].x = ((0.5 + cos(index * goldenAngle) * radius) * 720.0).toFloat()
            nodes[index].y = ((0.5 + sin(index * goldenAngle) * radius) * 420.0).toFloat()
        }
    }

    fun layout(nodes: List<GraphNode>, edges: List<GraphEdge>) {
        val count = nodes.size
        if (count <= 1) {
            golden(nodes)
            return
        }
        val positions = mutableListOf<LexiGraphForceVector>()
        val displacements = mutableListOf<LexiGraphForceVector>()
        val slots = mutableMapOf<String, Int>()
        val goldenAngle = Math.PI * (3.0 - sqrt(5.0))
        for (index in 0 until count) {
            val radius = sqrt((index + 0.5) / count)
            positions.add(
                LexiGraphForceVector(
                    x = cos(index * goldenAngle) * radius,
                    y = sin(index * goldenAngle) * radius
                )
            )
            displacements.add(LexiGraphForceVector())
            slots[nodes[index].id] = index
        }
        val spring = sqrt(4.0 / count) * 0.9
        val iterations = when {
            count > 320 -> 90
            count > 160 -> 120
            count > 80 -> 160
            else -> 260
        }
        val samples = min(96, count - 1)
        var temperature = 0.18
        for (iteration in 0 until iterations) {
            for (index in 0 until count) {
                displacements[index].x = 0.0
                displacements[index].y = 0.0
            }
            for (index in 0 until count) {
                val visits = if (count > 320) samples else count - index - 1
                val multiplier = if (count > 320) (count - 1.0) / (2.0 * samples) else 1.0
                for (visit in 0 until visits) {
                    val other = if (count > 320) {
                        (index + 1 + floor(visit * (count - 1.0) / samples).toInt() + iteration * 17) % count
                    } else {
                        index + 1 + visit
                    }
                    if (other == index) continue
                    var dx = positions[index].x - positions[other].x
                    var dy = positions[index].y - positions[other].y
                    var distance = sqrt(dx * dx + dy * dy)
                    if (distance < 0.0001) {
                        dx = 0.001 * (index - other)
                        dy = 0.001
                        distance = max(0.0015, sqrt(dx * dx + dy * dy))
                    }
                    val force = (spring * spring) / distance * multiplier
                    val fx = dx / distance * force
                    val fy = dy / distance * force
                    displacements[index].x += fx
                    displacements[index].y += fy
                    displacements[other].x -= fx
                    displacements[other].y -= fy
                }
            }
            for (edge in edges) {
                val start = slots[edge.sourceId] ?: continue
                val end = slots[edge.targetId] ?: continue
                val dx = positions[start].x - positions[end].x
                val dy = positions[start].y - positions[end].y
                val distance = max(0.0001, sqrt(dx * dx + dy * dy))
                val force = distance * distance / spring
                val fx = dx / distance * force
                val fy = dy / distance * force
                displacements[start].x -= fx
                displacements[start].y -= fy
                displacements[end].x += fx
                displacements[end].y += fy
            }
            for (index in 0 until count) {
                displacements[index].x -= positions[index].x * 0.6 * spring
                displacements[index].y -= positions[index].y * 0.6 * spring
                val length = max(
                    0.0001,
                    sqrt(
                        displacements[index].x * displacements[index].x +
                            displacements[index].y * displacements[index].y
                    )
                )
                val step = min(length, temperature)
                positions[index].x += displacements[index].x / length * step
                positions[index].y += displacements[index].y / length * step
            }
            temperature = max(0.004, temperature * 0.975)
        }
        var minX = Double.MAX_VALUE
        var maxX = -Double.MAX_VALUE
        var minY = Double.MAX_VALUE
        var maxY = -Double.MAX_VALUE
        for (pos in positions) {
            minX = min(minX, pos.x)
            maxX = max(maxX, pos.x)
            minY = min(minY, pos.y)
            maxY = max(maxY, pos.y)
        }
        val spanX = max(0.0001, maxX - minX)
        val spanY = max(0.0001, maxY - minY)
        for (index in 0 until count) {
            nodes[index].x = (((positions[index].x - minX) / spanX) * 580.0 + 70.0).toFloat()
            nodes[index].y = (((positions[index].y - minY) / spanY) * 320.0 + 50.0).toFloat()
        }
    }
}

/**
 * Builds the knowledge graph from saved relations and computes a deterministic force-directed layout normalised to [0, 1].
 * Exact 1:1 port of GraphLayout.ets.
 */
object GraphLayout {
    private fun topology(
        notes: List<NoteItem>,
        maps: List<MindMapDoc>,
        links: List<NoteLink>,
        includeMaps: Boolean,
        includeTags: Boolean
    ): GraphData {
        val data = GraphData()
        val index = mutableMapOf<String, GraphNode>()
        val edgeKeys = mutableSetOf<String>()
        val active = notes.filter { it.trashedAt == 0L }

        for (note in active) {
            val node = GraphNode(
                id = note.id,
                label = MarkdownEngine.displayTitle(note),
                kind = "note",
                noteType = note.noteType,
                tags = note.tags.toMutableList(),
                snippet = MarkdownEngine.extractSnippet(note).take(72)
            )
            index[node.id] = node
            data.nodes.add(node)
        }

        val addEdge = { sourceId: String, targetId: String, kind: String ->
            if (sourceId != targetId) {
                val a = index[sourceId]
                val b = index[targetId]
                if (a != null && b != null) {
                    val key = if (sourceId < targetId) "$sourceId|$targetId" else "$targetId|$sourceId"
                    if (!edgeKeys.contains(key)) {
                        edgeKeys.add(key)
                        data.edges.add(GraphEdge(sourceId = sourceId, targetId = targetId, kind = kind))
                        a.degree++
                        b.degree++
                    }
                }
            }
        }

        for (link in links) {
            if (link.targetId.isNotEmpty()) {
                addEdge(link.sourceId, link.targetId, "link")
            }
        }

        if (includeMaps) {
            for (map in maps) {
                if (map.trashedAt > 0L) continue
                val node = GraphNode(
                    id = "map:${map.id}",
                    label = map.title.ifEmpty { "未命名导图" },
                    kind = "mindmap",
                    snippet = "${map.nodes.size} 个节点的思维导图"
                )
                index[node.id] = node
                data.nodes.add(node)
                for (mapNode in map.nodes) {
                    if (mapNode.noteRefId.isNotEmpty()) {
                        addEdge(node.id, mapNode.noteRefId, "mapRef")
                    }
                }
            }
        }

        if (includeTags) {
            for (note in active) {
                for (tag in note.tags) {
                    val tagId = "tag:$tag"
                    if (!index.containsKey(tagId)) {
                        val node = GraphNode(
                            id = tagId,
                            label = "#$tag",
                            kind = "tag",
                            snippet = "标签"
                        )
                        index[tagId] = node
                        data.nodes.add(node)
                    }
                    addEdge(note.id, tagId, "tag")
                }
            }
        }

        return data
    }

    fun build(
        notes: List<NoteItem>,
        maps: List<MindMapDoc>,
        links: List<NoteLink>,
        includeMaps: Boolean,
        includeTags: Boolean
    ): GraphData {
        val data = topology(notes, maps, links, includeMaps, includeTags)
        layout(data.nodes, data.edges)
        return data
    }

    private fun localTopology(data: GraphData, focusId: String): GraphData {
        val keep = mutableSetOf(focusId)
        for (e in data.edges) {
            if (e.sourceId == focusId) {
                keep.add(e.targetId)
            } else if (e.targetId == focusId) {
                keep.add(e.sourceId)
            }
        }
        val result = GraphData()
        for (src in data.nodes) {
            if (keep.contains(src.id)) {
                result.nodes.add(src.copy(tags = src.tags.toMutableList()))
            }
        }
        result.edges = data.edges.filter { keep.contains(it.sourceId) && keep.contains(it.targetId) }.toMutableList()
        return result
    }

    fun local(data: GraphData, focusId: String): GraphData {
        val result = localTopology(data, focusId)
        layout(result.nodes, result.edges)
        return result
    }

    fun layout(nodes: List<GraphNode>, edges: List<GraphEdge>) {
        LexiGraphForce.layout(nodes, edges)
    }
}
