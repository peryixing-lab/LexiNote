package com.lovexjy.lexinote.ui.pages

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lovexjy.lexinote.core.*
import com.lovexjy.lexinote.ui.components.*
import kotlin.math.max
import kotlin.math.min

@Composable
fun MindMapScreen(
    initialDoc: MindMapDoc,
    allNotes: List<NoteItem>,
    palette: LexiThemePalette,
    onBack: () -> Unit,
    onSaved: (MindMapDoc) -> Unit,
    onOpenNote: (NoteItem) -> Unit,
    onConvertToNote: (MindMapDoc) -> Unit
) {
    var doc by remember(initialDoc.id) {
        val laidOut = MarkdownEngine.computeMindMapLayout(initialDoc.nodes, "right")
        mutableStateOf(initialDoc.copy(nodes = laidOut.toMutableList()))
    }
    var title by remember(initialDoc.id) { mutableStateOf(initialDoc.title) }
    var nodes by remember(initialDoc.id) { mutableStateOf<List<MindMapNode>>(doc.nodes) }
    var layoutDirection by remember { mutableStateOf("right") } // "right", "both", "org"
    var viewMode by remember { mutableStateOf("map") } // "map" or "outline"
    var selectedNodeId by remember(initialDoc.id) {
        mutableStateOf(doc.nodes.firstOrNull { it.parentId.isEmpty() }?.id ?: doc.nodes.firstOrNull()?.id ?: "")
    }
    var zoom by remember { mutableFloatStateOf(1f) }
    var panOffset by remember { mutableStateOf(Offset.Zero) }

    var undoStack by remember(initialDoc.id) { mutableStateOf(listOf<List<MindMapNode>>()) }
    var redoStack by remember(initialDoc.id) { mutableStateOf(listOf<List<MindMapNode>>()) }

    fun updateNodes(next: List<MindMapNode>, relayout: Boolean = true) {
        undoStack = (undoStack + listOf(nodes.map { it.copy() })).takeLast(25)
        redoStack = emptyList()
        nodes = if (relayout) {
            MarkdownEngine.computeMindMapLayout(next, layoutDirection)
        } else {
            next
        }
    }

    fun saveNow(): MindMapDoc {
        val updated = doc.copy(
            title = title.ifBlank { trText("未命名思维导图") },
            nodes = nodes.toMutableList(),
            updatedAt = System.currentTimeMillis()
        )
        val saved = LexiStorageService.saveMindMap(updated)
        doc = saved
        onSaved(saved)
        return saved
    }

    val selectedNode = remember(nodes, selectedNodeId) {
        nodes.firstOrNull { it.id == selectedNodeId } ?: nodes.firstOrNull()
    }

    val visibleNodes = remember(nodes) {
        val nodeMap = nodes.associateBy { it.id }
        fun isHidden(n: MindMapNode): Boolean {
            var curParentId = n.parentId
            var guard = 0
            while (curParentId.isNotEmpty() && guard < 50) {
                val p = nodeMap[curParentId] ?: break
                if (p.collapsed) return true
                curParentId = p.parentId
                guard++
            }
            return false
        }
        nodes.filterNot { isHidden(it) }
    }

    val colorPresets = listOf(
        "#6E44D9" to "紫晶",
        "#2B6CB0" to "靛蓝",
        "#2F855A" to "青翠",
        "#D69E2E" to "琥珀",
        "#B83280" to "暮粉"
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.bg_root.toComposeColor())
    ) {
        LexiBackHeader(
            title = trText("思维导图"),
            subtitle = "",
            rightText = trText("保存"),
            palette = palette,
            onBack = {
                saveNow()
                onBack()
            },
            onRightAction = { saveNow() }
        )

        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Top Title + Mode Switcher Card
            val headerShape = RoundedCornerShape(20.dp)
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .then(
                        com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                            elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                            shape = headerShape,
                            dark = palette.dark
                        )
                    )
                    .clip(headerShape)
                    .background(palette.surface_card.toComposeColor())
                    .padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(modifier = Modifier.weight(1f)) {
                        BasicTextField(
                            value = title,
                            onValueChange = { title = it },
                            singleLine = true,
                            textStyle = TextStyle(
                                color = palette.text_primary.toComposeColor(),
                                fontSize = 18.sp,
                                fontWeight = FontWeight.Bold
                            ),
                            cursorBrush = SolidColor(palette.brand.toComposeColor()),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        SmallControlChip(
                            text = trText("导图"),
                            palette = palette,
                            active = viewMode == "map",
                            onClick = { viewMode = "map" }
                        )
                        SmallControlChip(
                            text = trText("大纲"),
                            palette = palette,
                            active = viewMode == "outline",
                            onClick = { viewMode = "outline" }
                        )
                    }
                }

                // Action Toolbar
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    SmallControlChip(
                        text = trText("+ 子主题"),
                        palette = palette,
                        active = true,
                        onClick = {
                            val parent = selectedNode ?: nodes.firstOrNull() ?: return@SmallControlChip
                            val newNode = MindMapNode(
                                id = "mm_n_${System.currentTimeMillis()}",
                                text = trText("新子主题"),
                                parentId = parent.id,
                                color = parent.color
                            )
                            val next = nodes.map {
                                if (it.id == parent.id) it.copy(collapsed = false) else it
                            } + newNode
                            updateNodes(next, true)
                            selectedNodeId = newNode.id
                        }
                    )
                    SmallControlChip(
                        text = trText("+ 同级主题"),
                        palette = palette,
                        onClick = {
                            val current = selectedNode ?: return@SmallControlChip
                            val parentId = current.parentId.ifEmpty { current.id }
                            val newNode = MindMapNode(
                                id = "mm_n_${System.currentTimeMillis()}",
                                text = trText("同级主题"),
                                parentId = parentId,
                                color = current.color
                            )
                            updateNodes(nodes + newNode, true)
                            selectedNodeId = newNode.id
                        }
                    )
                    listOf(
                        "right" to "向右",
                        "both" to "双向",
                        "org" to "组织"
                    ).forEach { (dir, label) ->
                        SmallControlChip(
                            text = trText(label),
                            palette = palette,
                            active = layoutDirection == dir,
                            onClick = {
                                layoutDirection = dir
                                nodes = MarkdownEngine.computeMindMapLayout(nodes, dir)
                            }
                        )
                    }
                    SmallControlChip(
                        text = trText("撤销"),
                        palette = palette,
                        onClick = {
                            if (undoStack.isNotEmpty()) {
                                val prev = undoStack.last()
                                undoStack = undoStack.dropLast(1)
                                redoStack = redoStack + listOf(nodes)
                                nodes = prev
                            }
                        }
                    )
                    SmallControlChip(
                        text = trText("重做"),
                        palette = palette,
                        onClick = {
                            if (redoStack.isNotEmpty()) {
                                val next = redoStack.last()
                                redoStack = redoStack.dropLast(1)
                                undoStack = undoStack + listOf(nodes)
                                nodes = next
                            }
                        }
                    )
                    SmallControlChip(
                        text = trText("转为笔记"),
                        palette = palette,
                        onClick = {
                            val saved = saveNow()
                            onConvertToNote(saved)
                        }
                    )
                }
            }

            if (viewMode == "map") {
                // 2D Interactive MindMap Canvas Card
                val mapCardShape = RoundedCornerShape(20.dp)
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(
                            com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                                elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                                shape = mapCardShape,
                                dark = palette.dark
                            )
                        )
                        .clip(mapCardShape)
                        .background(palette.surface_card.toComposeColor())
                        .padding(12.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "${visibleNodes.size} / ${nodes.size} ${trText("个节点")}",
                            fontSize = 11.sp,
                            color = palette.text_muted.toComposeColor()
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            SmallControlChip(text = trText("适应画布"), palette = palette) {
                                zoom = 1f
                                panOffset = Offset.Zero
                            }
                            SmallControlChip(text = "-", palette = palette) {
                                zoom = max(0.55f, zoom - 0.15f)
                            }
                            SmallControlChip(text = "${(zoom * 100).toInt()}%", palette = palette) {
                                zoom = 1f
                            }
                            SmallControlChip(text = "+", palette = palette) {
                                zoom = min(2.0f, zoom + 0.15f)
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(8.dp))

                    BoxWithConstraints(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(320.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .background(palette.surface_soft.toComposeColor())
                            .pointerInput(Unit) {
                                detectTransformGestures { _, pan, gestureZoom, _ ->
                                    zoom = (zoom * gestureZoom).coerceIn(0.55f, 2.0f)
                                    panOffset += pan
                                }
                            }
                    ) {
                        val density = LocalDensity.current
                        val visibleMap = remember(visibleNodes) { visibleNodes.associateBy { it.id } }

                        Canvas(modifier = Modifier.fillMaxSize()) {
                            // Subtle dot grid
                            val step = 28f * zoom
                            if (step >= 14f) {
                                var gx = (panOffset.x % step + step) % step
                                while (gx < size.width) {
                                    var gy = (panOffset.y % step + step) % step
                                    while (gy < size.height) {
                                        drawCircle(
                                            color = palette.stroke.toComposeColor(),
                                            radius = 1.3f,
                                            center = Offset(gx, gy)
                                        )
                                        gy += step
                                    }
                                    gx += step
                                }
                            }

                            // Bezier edges
                            visibleNodes.forEach { child ->
                                if (child.parentId.isNotEmpty()) {
                                    val parent = visibleMap[child.parentId] ?: return@forEach
                                    val p1 = Offset(
                                        (parent.x + 65f) * zoom + panOffset.x,
                                        (parent.y + 18f) * zoom + panOffset.y
                                    )
                                    val p2 = Offset(
                                        child.x * zoom + panOffset.x,
                                        (child.y + 18f) * zoom + panOffset.y
                                    )
                                    val midX = (p1.x + p2.x) / 2f
                                    val path = Path().apply {
                                        moveTo(p1.x, p1.y)
                                        cubicTo(midX, p1.y, midX, p2.y, p2.x, p2.y)
                                    }
                                    drawPath(
                                        path = path,
                                        color = child.color.toComposeColor().copy(alpha = 0.65f),
                                        style = Stroke(width = 2.4f * zoom)
                                    )
                                }
                            }
                        }

                        // Node Cards Overlay
                        visibleNodes.forEach { node ->
                            val isSelected = node.id == selectedNode?.id
                            val isRoot = node.parentId.isEmpty()
                            val childCount = nodes.count { it.parentId == node.id }
                            val xDp = with(density) { (node.x * zoom + panOffset.x).toDp() }
                            val yDp = with(density) { (node.y * zoom + panOffset.y).toDp() }
                            val nodeColor = node.color.toComposeColor()

                            Row(
                                modifier = Modifier
                                    .offset(x = xDp, y = yDp)
                                    .widthIn(min = 84.dp, max = 160.dp)
                                    .clip(RoundedCornerShape(12.dp))
                                    .background(
                                        if (isRoot) nodeColor
                                        else palette.surface_card.toComposeColor()
                                    )
                                    .border(
                                        width = if (isSelected) 2.dp else 1.dp,
                                        color = if (isSelected) nodeColor else palette.stroke.toComposeColor(),
                                        shape = RoundedCornerShape(12.dp)
                                    )
                                    .clickable { selectedNodeId = node.id }
                                    .pointerInput(node.id, zoom) {
                                        detectDragGestures { change, dragAmount ->
                                            change.consume()
                                            selectedNodeId = node.id
                                            val dx = dragAmount.x / zoom
                                            val dy = dragAmount.y / zoom
                                            nodes = nodes.map {
                                                if (it.id == node.id) it.copy(x = it.x + dx, y = it.y + dy)
                                                else it
                                            }
                                        }
                                    }
                                    .padding(horizontal = 10.dp, vertical = 7.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                if (!isRoot) {
                                    Box(
                                        modifier = Modifier
                                            .size(8.dp)
                                            .clip(CircleShape)
                                            .background(nodeColor)
                                    )
                                    Spacer(modifier = Modifier.width(6.dp))
                                }
                                Text(
                                    text = node.text,
                                    fontSize = 12.sp,
                                    fontWeight = if (isRoot || isSelected) FontWeight.Bold else FontWeight.Medium,
                                    color = if (isRoot) Color.White else palette.text_primary.toComposeColor(),
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f, fill = false)
                                )
                                if (node.collapsed && childCount > 0) {
                                    Spacer(modifier = Modifier.width(4.dp))
                                    Text(
                                        text = "+$childCount",
                                        fontSize = 10.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = if (isRoot) Color.White else nodeColor
                                    )
                                }
                            }
                        }
                    }
                }
            } else {
                // Outline Tree View
                val outlineMd = remember(title, nodes) {
                    MarkdownEngine.mindMapToMarkdownOutline(title, nodes)
                }
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(20.dp))
                        .background(palette.surface_card.toComposeColor())
                        .border(1.dp, palette.stroke.toComposeColor(), RoundedCornerShape(20.dp))
                        .padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = trText("Markdown 结构化大纲预览"),
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold,
                            color = palette.text_primary.toComposeColor()
                        )
                        SmallControlChip(
                            text = trText("保存为笔记"),
                            palette = palette,
                            active = true,
                            onClick = {
                                val saved = saveNow()
                                onConvertToNote(saved)
                            }
                        )
                    }
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(palette.surface_soft.toComposeColor())
                            .padding(12.dp)
                    ) {
                        Text(
                            text = outlineMd,
                            fontSize = 12.sp,
                            fontFamily = FontFamily.Monospace,
                            color = palette.text_primary.toComposeColor()
                        )
                    }
                }
            }

            // Selected Node Inspector Card
            selectedNode?.let { node ->
                val isRoot = node.parentId.isEmpty()
                val hasChildren = nodes.any { it.parentId == node.id }
                val linkedNote = allNotes.firstOrNull { it.id == node.noteId }

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(20.dp))
                        .background(palette.surface_card.toComposeColor())
                        .border(1.dp, palette.stroke.toComposeColor(), RoundedCornerShape(20.dp))
                        .padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = if (isRoot) trText("中心主题属性") else trText("选中节点属性"),
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                            color = palette.text_primary.toComposeColor()
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            if (hasChildren) {
                                SmallControlChip(
                                    text = if (node.collapsed) trText("展开子节点") else trText("折叠子节点"),
                                    palette = palette,
                                    onClick = {
                                        val next = nodes.map {
                                            if (it.id == node.id) it.copy(collapsed = !it.collapsed) else it
                                        }
                                        updateNodes(next, false)
                                    }
                                )
                            }
                            if (!isRoot) {
                                SmallControlChip(
                                    text = trText("删除节点"),
                                    palette = palette,
                                    onClick = {
                                        val toRemove = mutableSetOf(node.id)
                                        var changed = true
                                        while (changed) {
                                            changed = false
                                            nodes.forEach { n ->
                                                if (n.parentId in toRemove && n.id !in toRemove) {
                                                    toRemove.add(n.id)
                                                    changed = true
                                                }
                                            }
                                        }
                                        val remaining = nodes.filterNot { it.id in toRemove }
                                        updateNodes(remaining, true)
                                        selectedNodeId = remaining.firstOrNull()?.id ?: ""
                                    }
                                )
                            }
                        }
                    }

                    OutlinedTextField(
                        value = node.text,
                        onValueChange = { txt ->
                            nodes = nodes.map { if (it.id == node.id) it.copy(text = txt) else it }
                        },
                        label = { Text(trText("主题名称")) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )

                    OutlinedTextField(
                        value = node.note,
                        onValueChange = { remark ->
                            nodes = nodes.map { if (it.id == node.id) it.copy(note = remark) else it }
                        },
                        label = { Text(trText("节点备注说明")) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )

                    // Color tags
                    Row(
                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = trText("配色:"),
                            fontSize = 12.sp,
                            color = palette.text_secondary.toComposeColor()
                        )
                        colorPresets.forEach { (hex, label) ->
                            val active = node.color.equals(hex, ignoreCase = true)
                            Row(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(999.dp))
                                    .background(if (active) hex.toComposeColor() else palette.surface_soft.toComposeColor())
                                    .clickable {
                                        nodes = nodes.map {
                                            if (it.id == node.id) it.copy(color = hex) else it
                                        }
                                    }
                                    .padding(horizontal = 10.dp, vertical = 4.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(8.dp)
                                        .clip(CircleShape)
                                        .background(if (active) Color.White else hex.toComposeColor())
                                )
                                Spacer(modifier = Modifier.width(4.dp))
                                Text(
                                    text = trText(label),
                                    fontSize = 11.sp,
                                    color = if (active) Color.White else palette.text_primary.toComposeColor()
                                )
                            }
                        }
                    }

                    // Linked Note Controls
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = if (linkedNote != null) "${trText("关联笔记")}: ${linkedNote.title}"
                            else trText("尚未关联知识库笔记"),
                            fontSize = 12.sp,
                            color = palette.text_secondary.toComposeColor(),
                            modifier = Modifier.weight(1f)
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            if (linkedNote != null) {
                                SmallControlChip(
                                    text = trText("跳转笔记"),
                                    palette = palette,
                                    active = true,
                                    onClick = {
                                        saveNow()
                                        onOpenNote(linkedNote)
                                    }
                                )
                            } else {
                                SmallControlChip(
                                    text = trText("从节点建笔记"),
                                    palette = palette,
                                    active = true,
                                    onClick = {
                                        val created = LexiStorageService.createNote(
                                            title = node.text,
                                            content = "# ${node.text}\n\n${node.note}\n",
                                            vaultId = doc.vaultId
                                        )
                                        nodes = nodes.map {
                                            if (it.id == node.id) it.copy(noteId = created.id) else it
                                        }
                                        saveNow()
                                        onOpenNote(created)
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun CanvasScreen(
    initialBoard: CanvasBoard,
    allNotes: List<NoteItem>,
    palette: LexiThemePalette,
    onBack: () -> Unit,
    onSaved: (CanvasBoard) -> Unit,
    onOpenNote: (NoteItem) -> Unit
) {
    var board by remember(initialBoard.id) { mutableStateOf(initialBoard.copy()) }
    var title by remember(initialBoard.id) { mutableStateOf(initialBoard.title) }
    var cards by remember(initialBoard.id) { mutableStateOf<List<CanvasCard>>(initialBoard.cards) }
    var edges by remember(initialBoard.id) { mutableStateOf<List<CanvasEdge>>(initialBoard.edges) }
    var selectedCardId by remember(initialBoard.id) {
        mutableStateOf(initialBoard.cards.firstOrNull()?.id ?: "")
    }
    var zoom by remember { mutableFloatStateOf(1f) }
    var panOffset by remember { mutableStateOf(Offset.Zero) }

    fun saveNow(): CanvasBoard {
        val updated = board.copy(
            title = title.ifBlank { trText("未命名白板") },
            cards = cards.toMutableList(),
            edges = edges.toMutableList(),
            updatedAt = System.currentTimeMillis()
        )
        val saved = LexiStorageService.saveCanvas(updated)
        board = saved
        onSaved(saved)
        return saved
    }

    val selectedCard = remember(cards, selectedCardId) {
        cards.firstOrNull { it.id == selectedCardId } ?: cards.firstOrNull()
    }

    val cardColorPresets = listOf(
        "#EAE1FF" to "薰衣草",
        "#E2E8F0" to "云雾灰",
        "#C6F6D5" to "薄荷绿",
        "#FEFCBF" to "暖阳黄",
        "#FED7E2" to "樱花粉"
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.bg_root.toComposeColor())
    ) {
        LexiBackHeader(
            title = trText("自由白板"),
            subtitle = "",
            rightText = trText("保存"),
            palette = palette,
            onBack = {
                saveNow()
                onBack()
            },
            onRightAction = { saveNow() }
        )

        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Top Title + Toolbar Card
            val cvHeaderShape = RoundedCornerShape(20.dp)
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .then(
                        com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                            elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                            shape = cvHeaderShape,
                            dark = palette.dark
                        )
                    )
                    .clip(cvHeaderShape)
                    .background(palette.surface_card.toComposeColor())
                    .padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                BasicTextField(
                    value = title,
                    onValueChange = { title = it },
                    singleLine = true,
                    textStyle = TextStyle(
                        color = palette.text_primary.toComposeColor(),
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold
                    ),
                    cursorBrush = SolidColor(palette.brand.toComposeColor()),
                    modifier = Modifier.fillMaxWidth()
                )

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    SmallControlChip(
                        text = trText("+ 新增卡片"),
                        palette = palette,
                        active = true,
                        onClick = {
                            val idx = cards.size
                            val newCard = CanvasCard(
                                id = "cv_c_${System.currentTimeMillis()}",
                                title = "${trText("灵感卡片")} ${idx + 1}",
                                content = trText("写下关键结论或关联笔记"),
                                x = 40f + (idx % 2) * 190f,
                                y = 40f + (idx / 2) * 125f,
                                width = 180f,
                                height = 105f,
                                color = "#EAE1FF"
                            )
                            cards = cards + newCard
                            selectedCardId = newCard.id
                        }
                    )
                    SmallControlChip(text = trText("适应画布"), palette = palette) {
                        zoom = 1f
                        panOffset = Offset.Zero
                    }
                    SmallControlChip(text = "-", palette = palette) {
                        zoom = max(0.55f, zoom - 0.15f)
                    }
                    SmallControlChip(text = "${(zoom * 100).toInt()}%", palette = palette) {
                        zoom = 1f
                    }
                    SmallControlChip(text = "+", palette = palette) {
                        zoom = min(2.0f, zoom + 0.15f)
                    }
                }
            }

            // 2D Interactive Canvas Board
            val cvBoardShape = RoundedCornerShape(20.dp)
            BoxWithConstraints(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(330.dp)
                    .then(
                        com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                            elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level1,
                            shape = cvBoardShape,
                            dark = palette.dark
                        )
                    )
                    .clip(cvBoardShape)
                    .background(palette.surface_card.toComposeColor())
                    .pointerInput(Unit) {
                        detectTransformGestures { _, pan, gestureZoom, _ ->
                            zoom = (zoom * gestureZoom).coerceIn(0.55f, 2.0f)
                            panOffset += pan
                        }
                    }
            ) {
                val density = LocalDensity.current
                val cardMap = remember(cards) { cards.associateBy { it.id } }

                Canvas(modifier = Modifier.fillMaxSize()) {
                    val step = 28f * zoom
                    if (step >= 14f) {
                        var gx = (panOffset.x % step + step) % step
                        while (gx < size.width) {
                            var gy = (panOffset.y % step + step) % step
                            while (gy < size.height) {
                                drawCircle(
                                    color = palette.stroke.toComposeColor(),
                                    radius = 1.3f,
                                    center = Offset(gx, gy)
                                )
                                gy += step
                            }
                            gx += step
                        }
                    }

                    edges.forEach { edge ->
                        val from = cardMap[edge.fromCardId] ?: return@forEach
                        val to = cardMap[edge.toCardId] ?: return@forEach
                        val p1 = Offset(
                            (from.x + from.width / 2f) * zoom + panOffset.x,
                            (from.y + from.height / 2f) * zoom + panOffset.y
                        )
                        val p2 = Offset(
                            (to.x + to.width / 2f) * zoom + panOffset.x,
                            (to.y + to.height / 2f) * zoom + panOffset.y
                        )
                        drawLine(
                            color = palette.brand.toComposeColor(),
                            start = p1,
                            end = p2,
                            strokeWidth = 2.4f * zoom
                        )
                    }
                }

                cards.forEach { card ->
                    val isSelected = card.id == selectedCard?.id
                    val xDp = with(density) { (card.x * zoom + panOffset.x).toDp() }
                    val yDp = with(density) { (card.y * zoom + panOffset.y).toDp() }
                    val wDp = with(density) { (card.width * zoom).coerceIn(120f, 260f).toDp() }

                    Column(
                        modifier = Modifier
                            .offset(x = xDp, y = yDp)
                            .width(wDp)
                            .clip(RoundedCornerShape(14.dp))
                            .background(card.color.toComposeColor())
                            .border(
                                width = if (isSelected) 2.dp else 1.dp,
                                color = if (isSelected) palette.brand.toComposeColor() else Color(0x33000000),
                                shape = RoundedCornerShape(14.dp)
                            )
                            .clickable { selectedCardId = card.id }
                            .pointerInput(card.id, zoom) {
                                detectDragGestures { change, dragAmount ->
                                    change.consume()
                                    selectedCardId = card.id
                                    val dx = dragAmount.x / zoom
                                    val dy = dragAmount.y / zoom
                                    cards = cards.map {
                                        if (it.id == card.id) it.copy(x = it.x + dx, y = it.y + dy)
                                        else it
                                    }
                                }
                            }
                            .padding(10.dp)
                    ) {
                        Text(
                            text = card.title,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color(0xFF1F1635),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = card.content,
                            fontSize = 11.sp,
                            color = Color(0xFF4A3D68),
                            maxLines = 3,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }

            // Selected Card Inspector
            selectedCard?.let { card ->
                val linkedNote = allNotes.firstOrNull { it.id == card.noteId }
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(20.dp))
                        .background(palette.surface_card.toComposeColor())
                        .border(1.dp, palette.stroke.toComposeColor(), RoundedCornerShape(20.dp))
                        .padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = trText("选中白板卡片"),
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                            color = palette.text_primary.toComposeColor()
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            listOf(
                                "←" to Offset(-20f, 0f),
                                "↑" to Offset(0f, -20f),
                                "↓" to Offset(0f, 20f),
                                "→" to Offset(20f, 0f)
                            ).forEach { (arrow, delta) ->
                                SmallControlChip(text = arrow, palette = palette) {
                                    cards = cards.map {
                                        if (it.id == card.id) it.copy(x = it.x + delta.x, y = it.y + delta.y)
                                        else it
                                    }
                                }
                            }
                            if (cards.size > 1) {
                                SmallControlChip(text = trText("删除"), palette = palette) {
                                    cards = cards.filterNot { it.id == card.id }
                                    edges = edges.filterNot { it.fromCardId == card.id || it.toCardId == card.id }
                                    selectedCardId = cards.firstOrNull()?.id ?: ""
                                }
                            }
                        }
                    }

                    OutlinedTextField(
                        value = card.title,
                        onValueChange = { t ->
                            cards = cards.map { if (it.id == card.id) it.copy(title = t) else it }
                        },
                        label = { Text(trText("卡片标题")) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )

                    OutlinedTextField(
                        value = card.content,
                        onValueChange = { c ->
                            cards = cards.map { if (it.id == card.id) it.copy(content = c) else it }
                        },
                        label = { Text(trText("卡片内容")) },
                        minLines = 2,
                        maxLines = 4,
                        modifier = Modifier.fillMaxWidth()
                    )

                    // Card Color Selector
                    Row(
                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = trText("底色:"),
                            fontSize = 12.sp,
                            color = palette.text_secondary.toComposeColor()
                        )
                        cardColorPresets.forEach { (hex, label) ->
                            val active = card.color.equals(hex, ignoreCase = true)
                            SmallControlChip(
                                text = trText(label),
                                palette = palette,
                                active = active,
                                onClick = {
                                    cards = cards.map {
                                        if (it.id == card.id) it.copy(color = hex) else it
                                    }
                                }
                            )
                        }
                    }

                    // Connect / Disconnect Other Cards
                    val otherCards = cards.filterNot { it.id == card.id }
                    if (otherCards.isNotEmpty()) {
                        Text(
                            text = trText("点击与其他卡片建立或断开连线："),
                            fontSize = 12.sp,
                            color = palette.text_secondary.toComposeColor()
                        )
                        Row(
                            modifier = Modifier.horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            otherCards.forEach { target ->
                                val connected = edges.any {
                                    (it.fromCardId == card.id && it.toCardId == target.id) ||
                                        (it.fromCardId == target.id && it.toCardId == card.id)
                                }
                                SmallControlChip(
                                    text = (if (connected) "🔗 " else "+ ") + target.title,
                                    palette = palette,
                                    active = connected,
                                    onClick = {
                                        edges = if (connected) {
                                            edges.filterNot {
                                                (it.fromCardId == card.id && it.toCardId == target.id) ||
                                                    (it.fromCardId == target.id && it.toCardId == card.id)
                                            }
                                        } else {
                                            edges + CanvasEdge(
                                                id = "cv_e_${System.currentTimeMillis()}",
                                                fromCardId = card.id,
                                                toCardId = target.id,
                                                label = "关联"
                                            )
                                        }
                                    }
                                )
                            }
                        }
                    }

                    // Vault Note Association
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = if (linkedNote != null) "${trText("关联笔记")}: ${linkedNote.title}"
                            else trText("未关联知识库笔记"),
                            fontSize = 12.sp,
                            color = palette.text_secondary.toComposeColor(),
                            modifier = Modifier.weight(1f)
                        )
                        if (linkedNote != null) {
                            SmallControlChip(
                                text = trText("打开关联笔记"),
                                palette = palette,
                                active = true,
                                onClick = {
                                    saveNow()
                                    onOpenNote(linkedNote)
                                }
                            )
                        } else {
                            SmallControlChip(
                                text = trText("转为新笔记"),
                                palette = palette,
                                active = true,
                                onClick = {
                                    val created = LexiStorageService.createNote(
                                        title = card.title,
                                        content = "# ${card.title}\n\n${card.content}\n",
                                        vaultId = board.vaultId
                                    )
                                    cards = cards.map {
                                        if (it.id == card.id) it.copy(noteId = created.id) else it
                                    }
                                    saveNow()
                                    onOpenNote(created)
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}
