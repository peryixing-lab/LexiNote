package com.lovexjy.lexinote.ui.components

import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import com.lovexjy.lexinote.core.*
import java.util.Locale

@Composable
fun LexiTemplatePickerDialog(
    palette: LexiThemePalette,
    onDismiss: () -> Unit,
    onSelectTemplate: (LexiTemplateItem) -> Unit
) {
    var refreshTick by remember { mutableIntStateOf(0) }
    val templates = remember(refreshTick) { LexiStorageService.listTemplates() }
    val defaultDailyId = remember(refreshTick) { LexiStorageService.getDefaultDailyTemplateId() }
    var selectedCategory by remember { mutableStateOf("全部") }
    var editingTemplate by remember { mutableStateOf<LexiTemplateItem?>(null) }
    var showEditModal by remember { mutableStateOf(false) }

    val categories = listOf("全部", "内置", "自定义", "日常", "学习", "工程", "管理", "决策")
    val filtered = remember(templates, selectedCategory) {
        templates.filter { tpl ->
            when (selectedCategory) {
                "全部" -> true
                "内置" -> tpl.builtin
                "自定义" -> !tpl.builtin
                else -> tpl.category == selectedCategory
            }
        }
    }

    Dialog(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 580.dp)
                .clip(RoundedCornerShape(24.dp))
                .background(palette.surface_card.toComposeColor())
                .border(1.dp, palette.stroke.toComposeColor(), RoundedCornerShape(24.dp))
                .padding(18.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = trText("选择笔记模板"),
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.text_primary.toComposeColor()
                    )
                    Text(
                        text = trText("支持 {{date}}、{{time}}、{{vault}}、{{project}} 变量替换"),
                        fontSize = 11.sp,
                        color = palette.text_muted.toComposeColor()
                    )
                }
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(14.dp))
                        .background(palette.brand_soft.toComposeColor())
                        .clickable {
                            editingTemplate = LexiTemplateItem(
                                id = "",
                                name = "",
                                category = "自定义",
                                description = "",
                                titlePattern = "{{title}}",
                                tags = mutableListOf("模板"),
                                content = "# {{title}}\n\n",
                                builtin = false
                            )
                            showEditModal = true
                        }
                        .padding(horizontal = 12.dp, vertical = 6.dp)
                ) {
                    Text(
                        text = trText("+ 新建模板"),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.brand.toComposeColor()
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                categories.forEach { cat ->
                    SmallControlChip(
                        text = trText(cat),
                        palette = palette,
                        active = selectedCategory == cat,
                        onClick = { selectedCategory = cat }
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))
            Column(
                modifier = Modifier
                    .weight(1f, fill = false)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                filtered.forEach { tpl ->
                    val isDefaultDaily = tpl.id == defaultDailyId
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .background(palette.surface_soft.toComposeColor())
                            .border(
                                1.dp,
                                if (isDefaultDaily) palette.brand.toComposeColor() else palette.stroke.toComposeColor(),
                                RoundedCornerShape(16.dp)
                            )
                            .clickable { onSelectTemplate(tpl) }
                            .padding(14.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    text = trText(tpl.name),
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = palette.text_primary.toComposeColor()
                                )
                                Spacer(modifier = Modifier.width(6.dp))
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(999.dp))
                                        .background(palette.chip_bg.toComposeColor())
                                        .padding(horizontal = 7.dp, vertical = 2.dp)
                                ) {
                                    Text(
                                        text = trText(tpl.category),
                                        fontSize = 10.sp,
                                        color = palette.text_secondary.toComposeColor()
                                    )
                                }
                                if (isDefaultDaily) {
                                    Spacer(modifier = Modifier.width(4.dp))
                                    Box(
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(999.dp))
                                            .background(palette.brand_soft.toComposeColor())
                                            .padding(horizontal = 7.dp, vertical = 2.dp)
                                    ) {
                                        Text(
                                            text = trText("今日默认"),
                                            fontSize = 10.sp,
                                            color = palette.brand.toComposeColor()
                                        )
                                    }
                                }
                            }
                            Text(
                                text = trText("使用"),
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                color = palette.brand.toComposeColor()
                            )
                        }
                        if (tpl.description.isNotBlank()) {
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                text = trText(tpl.description),
                                fontSize = 12.sp,
                                color = palette.text_secondary.toComposeColor()
                            )
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = if (isDefaultDaily) trText("已设为今日笔记默认模板") else trText("设为今日笔记默认"),
                                fontSize = 11.sp,
                                color = if (isDefaultDaily) palette.text_muted.toComposeColor() else palette.brand.toComposeColor(),
                                modifier = Modifier.clickable {
                                    LexiStorageService.setDefaultDailyTemplateId(tpl.id)
                                    refreshTick += 1
                                }
                            )
                            if (!tpl.builtin) {
                                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Text(
                                        text = trText("编辑"),
                                        fontSize = 11.sp,
                                        color = palette.text_secondary.toComposeColor(),
                                        modifier = Modifier.clickable {
                                            editingTemplate = tpl
                                            showEditModal = true
                                        }
                                    )
                                    Text(
                                        text = trText("删除"),
                                        fontSize = 11.sp,
                                        color = palette.danger.toComposeColor(),
                                        modifier = Modifier.clickable {
                                            LexiStorageService.deleteCustomTemplate(tpl.id)
                                            refreshTick += 1
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onDismiss) {
                    Text(text = trText("关闭"), color = palette.text_secondary.toComposeColor())
                }
            }
        }
    }

    if (showEditModal && editingTemplate != null) {
        val draft = editingTemplate!!
        var name by remember(draft) { mutableStateOf(draft.name) }
        var desc by remember(draft) { mutableStateOf(draft.description) }
        var titlePat by remember(draft) { mutableStateOf(draft.titlePattern) }
        var tagsText by remember(draft) { mutableStateOf(draft.tags.joinToString(", ")) }
        var content by remember(draft) { mutableStateOf(draft.content) }

        Dialog(onDismissRequest = { showEditModal = false }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(22.dp))
                    .background(palette.surface_card.toComposeColor())
                    .border(1.dp, palette.stroke.toComposeColor(), RoundedCornerShape(22.dp))
                    .padding(18.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(
                    text = if (draft.id.isEmpty()) trText("新建自定义模板") else trText("编辑自定义模板"),
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = palette.text_primary.toComposeColor()
                )
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(trText("模板名称")) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = desc,
                    onValueChange = { desc = it },
                    label = { Text(trText("模板说明")) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = titlePat,
                    onValueChange = { titlePat = it },
                    label = { Text(trText("默认标题格式 (如 {{date}} 周报)")) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = tagsText,
                    onValueChange = { tagsText = it },
                    label = { Text(trText("预设标签 (逗号分隔)")) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = content,
                    onValueChange = { content = it },
                    label = { Text(trText("Markdown 模板内容")) },
                    minLines = 5,
                    maxLines = 8,
                    modifier = Modifier.fillMaxWidth()
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    TextButton(onClick = { showEditModal = false }) {
                        Text(trText("取消"), color = palette.text_secondary.toComposeColor())
                    }
                    Spacer(modifier = Modifier.width(6.dp))
                    Button(
                        onClick = {
                            if (name.isNotBlank()) {
                                val tags = tagsText.split(",", "，")
                                    .map { it.trim() }
                                    .filter { it.isNotEmpty() }
                                LexiStorageService.saveCustomTemplate(
                                    draft.copy(
                                        name = name.trim(),
                                        description = desc.trim(),
                                        titlePattern = titlePat.ifBlank { "{{title}}" },
                                        tags = tags.toMutableList(),
                                        content = content
                                    )
                                )
                                showEditModal = false
                                refreshTick += 1
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = palette.brand.toComposeColor())
                    ) {
                        Text(trText("保存模板"), color = Color.White)
                    }
                }
            }
        }
    }
}

@Composable
fun LexiNoteDestinationPickerDialog(
    title: String = "选择归属工作区与笔记本",
    palette: LexiThemePalette,
    onDismiss: () -> Unit,
    onConfirm: (String, String) -> Unit
) {
    val vaults = remember { LexiStorageService.listVaults(false) }
    var selectedVaultId by remember {
        mutableStateOf(LexiStorageService.getActiveVaultId().ifEmpty { vaults.firstOrNull()?.id ?: "vault_default" })
    }
    val projects = remember(selectedVaultId) { LexiStorageService.listProjects(selectedVaultId) }
    var selectedProjectId by remember(selectedVaultId) {
        mutableStateOf(projects.firstOrNull()?.id ?: "")
    }

    Dialog(onDismissRequest = onDismiss) {
        val sheetShape = RoundedCornerShape(com.lovexjy.lexinote.ui.theme.LexiTokens.Radius.Sheet)
        com.lovexjy.lexinote.ui.theme.LexiAnimatedDialogBox {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .then(
                    com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                        elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level2,
                        shape = sheetShape,
                        dark = palette.dark
                    )
                )
                .clip(sheetShape)
                .background(palette.surface_card.toComposeColor())
                .border(com.lovexjy.lexinote.ui.theme.LexiTokens.Border.Hairline, palette.stroke.toComposeColor(), sheetShape)
                .padding(18.dp)
        ) {
            Text(
                text = trText(title),
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
                color = palette.text_primary.toComposeColor()
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = trText("选择笔记存放的工作区与项目分类"),
                fontSize = 12.sp,
                color = palette.text_muted.toComposeColor()
            )

            Spacer(modifier = Modifier.height(14.dp))
            Text(
                text = trText("工作区"),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = palette.text_secondary.toComposeColor()
            )
            Spacer(modifier = Modifier.height(6.dp))
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                vaults.forEach { v ->
                    val active = v.id == selectedVaultId
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(if (active) palette.brand_soft.toComposeColor() else palette.surface_soft.toComposeColor())
                            .border(
                                1.dp,
                                if (active) palette.brand.toComposeColor() else palette.stroke.toComposeColor(),
                                RoundedCornerShape(12.dp)
                            )
                            .clickable { selectedVaultId = v.id }
                            .padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        LexiIcon(name = "folder", size = 16.dp, palette = palette)
                        Spacer(modifier = Modifier.width(8.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = v.name,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (active) palette.brand.toComposeColor() else palette.text_primary.toComposeColor()
                            )
                            if (v.description.isNotBlank()) {
                                Text(
                                    text = v.description,
                                    fontSize = 11.sp,
                                    color = palette.text_muted.toComposeColor()
                                )
                            }
                        }
                    }
                }
            }

            if (projects.isNotEmpty()) {
                Spacer(modifier = Modifier.height(14.dp))
                Text(
                    text = trText("笔记本 / 项目"),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = palette.text_secondary.toComposeColor()
                )
                Spacer(modifier = Modifier.height(6.dp))
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    projects.forEach { proj ->
                        SmallControlChip(
                            text = proj.name,
                            palette = palette,
                            active = proj.id == selectedProjectId,
                            onClick = { selectedProjectId = proj.id }
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(18.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onDismiss) {
                    Text(trText("取消"), color = palette.text_secondary.toComposeColor())
                }
                Spacer(modifier = Modifier.width(6.dp))
                Button(
                    onClick = { onConfirm(selectedVaultId, selectedProjectId) },
                    colors = ButtonDefaults.buttonColors(containerColor = palette.brand.toComposeColor())
                ) {
                    Text(trText("确定"), color = Color.White)
                }
            }
        }
        }
    }
}

@Composable
fun LexiMobilePluginSheet(
    palette: LexiThemePalette,
    onDismiss: () -> Unit,
    onExecuteCommand: (LexiPluginRecord, String) -> Unit,
    onOpenPluginSettings: () -> Unit
) {
    val plugins = remember { LexiStorageService.listPlugins() }
    val enabledPlugins = remember(plugins) { plugins.filter { it.enabled } }

    Dialog(onDismissRequest = onDismiss) {
        val sheetShape = RoundedCornerShape(com.lovexjy.lexinote.ui.theme.LexiTokens.Radius.Sheet)
        com.lovexjy.lexinote.ui.theme.LexiAnimatedDialogBox {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .then(
                    com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                        elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level2,
                        shape = sheetShape,
                        dark = palette.dark
                    )
                )
                .clip(sheetShape)
                .background(palette.surface_card.toComposeColor())
                .border(com.lovexjy.lexinote.ui.theme.LexiTokens.Border.Hairline, palette.stroke.toComposeColor(), sheetShape)
                .padding(18.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    LexiIcon(name = "plugin", size = 18.dp, palette = palette)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = trText("知萤扩展插件"),
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.text_primary.toComposeColor()
                    )
                }
                Text(
                    text = trText("管理插件"),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = palette.brand.toComposeColor(),
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(palette.brand_soft.toComposeColor())
                        .clickable {
                            onDismiss()
                            onOpenPluginSettings()
                        }
                        .padding(horizontal = 10.dp, vertical = 5.dp)
                )
            }

            Spacer(modifier = Modifier.height(12.dp))
            if (enabledPlugins.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(palette.surface_soft.toComposeColor())
                        .padding(16.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = trText("当前暂无已启用插件，可前往「设置 -> 插件」开启"),
                        fontSize = 12.sp,
                        color = palette.text_muted.toComposeColor()
                    )
                }
            } else {
                Column(
                    modifier = Modifier
                        .heightIn(max = 380.dp)
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    enabledPlugins.forEach { plugin ->
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(16.dp))
                                .background(palette.surface_soft.toComposeColor())
                                .border(1.dp, palette.stroke.toComposeColor(), RoundedCornerShape(16.dp))
                                .padding(12.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = trText(plugin.name),
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = palette.text_primary.toComposeColor()
                                )
                                Text(
                                    text = "v${plugin.version}",
                                    fontSize = 11.sp,
                                    color = palette.text_muted.toComposeColor()
                                )
                            }
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                text = trText(plugin.description),
                                fontSize = 12.sp,
                                color = palette.text_secondary.toComposeColor()
                            )
                            if (plugin.commands.isNotEmpty()) {
                                Spacer(modifier = Modifier.height(8.dp))
                                Row(
                                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    plugin.commands.forEach { cmd ->
                                        Box(
                                            modifier = Modifier
                                                .clip(RoundedCornerShape(999.dp))
                                                .background(palette.brand_soft.toComposeColor())
                                                .clickable {
                                                    onDismiss()
                                                    onExecuteCommand(plugin, cmd)
                                                }
                                                .padding(horizontal = 10.dp, vertical = 5.dp)
                                        ) {
                                            Text(
                                                text = "▶ ${trText(cmd)}",
                                                fontSize = 11.sp,
                                                fontWeight = FontWeight.Medium,
                                                color = palette.brand.toComposeColor()
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onDismiss) {
                    Text(trText("关闭"), color = palette.text_secondary.toComposeColor())
                }
            }
        }
        }
    }
}

@Composable
fun LexiCaptureAssistantDialog(
    noteTitle: String,
    noteContent: String,
    allNotes: List<NoteItem>,
    initialTab: String = "voice",
    palette: LexiThemePalette,
    onDismiss: () -> Unit,
    onInsertMarkdown: (String) -> Unit,
    onAddTag: (String) -> Unit
) {
    val context = LocalContext.current
    var activeTab by remember { mutableStateOf(initialTab) }
    var voiceText by remember { mutableStateOf("") }
    var isListening by remember { mutableStateOf(false) }
    var speechStatus by remember { mutableStateOf("点击下方按钮开始语音听写，或直接输入语音速记") }

    val arrangement = remember(noteTitle, noteContent, allNotes) {
        LexiLocalAssistant.arrange(noteTitle, noteContent, allNotes)
    }

    DisposableEffect(Unit) {
        onDispose {
            // Clean up any recognizer on dialog exit
        }
    }

    Dialog(onDismissRequest = onDismiss) {
        val sheetShape = RoundedCornerShape(com.lovexjy.lexinote.ui.theme.LexiTokens.Radius.Sheet)
        com.lovexjy.lexinote.ui.theme.LexiAnimatedDialogBox {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 560.dp)
                .then(
                    com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                        elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level2,
                        shape = sheetShape,
                        dark = palette.dark
                    )
                )
                .clip(sheetShape)
                .background(palette.surface_card.toComposeColor())
                .border(com.lovexjy.lexinote.ui.theme.LexiTokens.Border.Hairline, palette.stroke.toComposeColor(), sheetShape)
                .padding(18.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = trText("离线语音与本地整理助手"),
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                    color = palette.text_primary.toComposeColor()
                )
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    SmallControlChip(
                        text = trText("离线语音"),
                        palette = palette,
                        active = activeTab == "voice",
                        onClick = { activeTab = "voice" }
                    )
                    SmallControlChip(
                        text = trText("本地整理"),
                        palette = palette,
                        active = activeTab == "arrange",
                        onClick = { activeTab = "arrange" }
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            if (activeTab == "voice") {
                Text(
                    text = trText(speechStatus),
                    fontSize = 12.sp,
                    color = palette.text_secondary.toComposeColor()
                )
                Spacer(modifier = Modifier.height(8.dp))
                OutlinedTextField(
                    value = voiceText,
                    onValueChange = { voiceText = it },
                    placeholder = { Text(trText("语音转写内容将显示在这里，也可手动编辑...")) },
                    minLines = 4,
                    maxLines = 7,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(10.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(18.dp))
                            .background(
                                if (isListening) palette.danger.toComposeColor()
                                else palette.brand_soft.toComposeColor()
                            )
                            .clickable {
                                if (!SpeechRecognizer.isRecognitionAvailable(context)) {
                                    speechStatus = "当前设备未启用系统离线语音服务，可使用键盘语音输入"
                                } else {
                                    isListening = !isListening
                                    speechStatus = if (isListening) "正在聆听系统语音输入..." else "已暂停语音识别"
                                }
                            }
                            .padding(horizontal = 14.dp, vertical = 8.dp)
                    ) {
                        Text(
                            text = if (isListening) trText("■ 停止听写") else trText("🎙 开始语音听写"),
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (isListening) Color.White else palette.brand.toComposeColor()
                        )
                    }

                    Button(
                        onClick = {
                            if (voiceText.isNotBlank()) {
                                onInsertMarkdown("\n" + voiceText.trim() + "\n")
                                onDismiss()
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = palette.brand.toComposeColor())
                    ) {
                        Text(trText("插入到笔记"), color = Color.White, fontSize = 12.sp)
                    }
                }
            } else {
                Column(
                    modifier = Modifier
                        .weight(1f, fill = false)
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text(
                        text = trText("基于本地启发式引擎自动提取摘要、待办、关联与标签（无需联网）："),
                        fontSize = 11.sp,
                        color = palette.text_muted.toComposeColor()
                    )

                    if (arrangement.summaryBullets.isNotEmpty()) {
                        AssistantSectionCard(
                            title = "核心摘要 (${arrangement.summaryBullets.size})",
                            items = arrangement.summaryBullets,
                            palette = palette,
                            actionText = "插入摘要",
                            onAction = {
                                val md = "\n## 核心摘要\n" + arrangement.summaryBullets.joinToString("\n") { "- $it" } + "\n"
                                onInsertMarkdown(md)
                                onDismiss()
                            }
                        )
                    }

                    if (arrangement.actionItems.isNotEmpty()) {
                        AssistantSectionCard(
                            title = "行动待办 (${arrangement.actionItems.size})",
                            items = arrangement.actionItems,
                            palette = palette,
                            actionText = "插入待办",
                            onAction = {
                                val md = "\n## 行动待办\n" + arrangement.actionItems.joinToString("\n") { "- [ ] $it" } + "\n"
                                onInsertMarkdown(md)
                                onDismiss()
                            }
                        )
                    }

                    if (arrangement.candidateLinks.isNotEmpty()) {
                        AssistantSectionCard(
                            title = "推荐双链 (${arrangement.candidateLinks.size})",
                            items = arrangement.candidateLinks.map { "[[$it]]" },
                            palette = palette,
                            actionText = "插入链接",
                            onAction = {
                                val md = "\n## 关联笔记\n" + arrangement.candidateLinks.joinToString("\n") { "- [[$it]]" } + "\n"
                                onInsertMarkdown(md)
                                onDismiss()
                            }
                        )
                    }

                    if (arrangement.candidateTags.isNotEmpty()) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(14.dp))
                                .background(palette.surface_soft.toComposeColor())
                                .padding(12.dp)
                        ) {
                            Text(
                                text = trText("建议标签（点击添加）"),
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                color = palette.text_primary.toComposeColor()
                            )
                            Spacer(modifier = Modifier.height(6.dp))
                            Row(
                                modifier = Modifier.horizontalScroll(rememberScrollState()),
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                arrangement.candidateTags.forEach { tag ->
                                    SmallControlChip(
                                        text = "+ #$tag",
                                        palette = palette,
                                        onClick = { onAddTag(tag) }
                                    )
                                }
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(10.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onDismiss) {
                    Text(trText("关闭"), color = palette.text_secondary.toComposeColor())
                }
            }
        }
        }
    }
}

@Composable
private fun AssistantSectionCard(
    title: String,
    items: List<String>,
    palette: LexiThemePalette,
    actionText: String,
    onAction: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(palette.surface_soft.toComposeColor())
            .border(1.dp, palette.stroke.toComposeColor(), RoundedCornerShape(14.dp))
            .padding(12.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = trText(title),
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                color = palette.text_primary.toComposeColor()
            )
            Text(
                text = trText(actionText),
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                color = palette.brand.toComposeColor(),
                modifier = Modifier.clickable { onAction() }
            )
        }
        Spacer(modifier = Modifier.height(6.dp))
        items.take(4).forEach { line ->
            Text(
                text = "• $line",
                fontSize = 12.sp,
                color = palette.text_secondary.toComposeColor(),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
fun LexiHistoryDialog(
    note: NoteItem,
    palette: LexiThemePalette,
    onDismiss: () -> Unit,
    onCreateSnapshot: () -> Unit,
    onRestoreRevision: (NoteRevision) -> Unit
) {
    var refreshTick by remember { mutableIntStateOf(0) }
    val revisions = remember(note.id, refreshTick) { LexiStorageService.listNoteRevisions(note.id) }
    var selectedRev by remember(revisions) { mutableStateOf(revisions.firstOrNull()) }
    var viewMode by remember { mutableStateOf("diff") } // "diff" or "full"

    val diffResult = remember(selectedRev, note.content) {
        if (selectedRev != null) {
            LexiNoteHistory.diffVersions(selectedRev!!.content, note.content)
        } else null
    }

    Dialog(onDismissRequest = onDismiss) {
        val sheetShape = RoundedCornerShape(com.lovexjy.lexinote.ui.theme.LexiTokens.Radius.Sheet)
        com.lovexjy.lexinote.ui.theme.LexiAnimatedDialogBox {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 600.dp)
                .then(
                    com.lovexjy.lexinote.ui.theme.LexiTokens.cardShadow(
                        elevation = com.lovexjy.lexinote.ui.theme.LexiTokens.Elev.Level2,
                        shape = sheetShape,
                        dark = palette.dark
                    )
                )
                .clip(sheetShape)
                .background(palette.surface_card.toComposeColor())
                .border(com.lovexjy.lexinote.ui.theme.LexiTokens.Border.Hairline, palette.stroke.toComposeColor(), sheetShape)
                .padding(18.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = trText("版本历史与快照对比"),
                        style = com.lovexjy.lexinote.ui.theme.LexiTokens.Type.H3,
                        color = palette.text_primary.toComposeColor()
                    )
                    Text(
                        text = "${revisions.size} 个历史版本",
                        style = com.lovexjy.lexinote.ui.theme.LexiTokens.Type.TnumMicro,
                        color = palette.text_muted.toComposeColor()
                    )
                }
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(14.dp))
                        .background(palette.brand_soft.toComposeColor())
                        .clickable {
                            onCreateSnapshot()
                            refreshTick += 1
                        }
                        .padding(horizontal = 12.dp, vertical = 6.dp)
                ) {
                    Text(
                        text = trText("+ 立即创建快照"),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.brand.toComposeColor()
                    )
                }
            }

            Spacer(modifier = Modifier.height(10.dp))
            if (revisions.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 28.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = trText("当前笔记尚无历史快照，点击右上角即可保存当前状态"),
                        fontSize = 12.sp,
                        color = palette.text_muted.toComposeColor()
                    )
                }
            } else {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    revisions.forEach { rev ->
                        val active = selectedRev?.id == rev.id
                        Column(
                            modifier = Modifier
                                .clip(RoundedCornerShape(12.dp))
                                .background(if (active) palette.brand_soft.toComposeColor() else palette.surface_soft.toComposeColor())
                                .border(
                                    1.dp,
                                    if (active) palette.brand.toComposeColor() else palette.stroke.toComposeColor(),
                                    RoundedCornerShape(12.dp)
                                )
                                .clickable { selectedRev = rev }
                                .padding(horizontal = 10.dp, vertical = 6.dp)
                        ) {
                            Text(
                                text = LexiNoteHistory.reasonLabel(rev.reason),
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (active) palette.brand.toComposeColor() else palette.text_primary.toComposeColor()
                            )
                            Text(
                                text = formatTimeShort(rev.savedAt),
                                fontSize = 10.sp,
                                color = palette.text_muted.toComposeColor()
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(10.dp))
                selectedRev?.let { rev ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            SmallControlChip(
                                text = trText("对比当前"),
                                palette = palette,
                                active = viewMode == "diff",
                                onClick = { viewMode = "diff" }
                            )
                            SmallControlChip(
                                text = trText("全文预览"),
                                palette = palette,
                                active = viewMode == "full",
                                onClick = { viewMode = "full" }
                            )
                        }
                        if (diffResult != null && viewMode == "diff") {
                            Text(
                                text = "+${diffResult.addedCount} / -${diffResult.removedCount}",
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = palette.text_secondary.toComposeColor()
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(8.dp))
                    Column(
                        modifier = Modifier
                            .weight(1f, fill = false)
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(palette.surface_soft.toComposeColor())
                            .padding(10.dp)
                            .verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(3.dp)
                    ) {
                        if (viewMode == "diff" && diffResult != null) {
                            diffResult.lines.forEach { dl ->
                                val bg = when (dl.kind) {
                                    "add" -> Color(0x222F855A)
                                    "remove" -> Color(0x22C53030)
                                    else -> Color.Transparent
                                }
                                val fg = when (dl.kind) {
                                    "add" -> palette.success.toComposeColor()
                                    "remove" -> palette.danger.toComposeColor()
                                    else -> palette.text_secondary.toComposeColor()
                                }
                                val prefix = when (dl.kind) {
                                    "add" -> "+ "
                                    "remove" -> "- "
                                    else -> "  "
                                }
                                Text(
                                    text = prefix + dl.text,
                                    fontSize = 11.sp,
                                    fontFamily = FontFamily.Monospace,
                                    color = fg,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .background(bg)
                                        .padding(horizontal = 4.dp, vertical = 1.dp)
                                )
                            }
                        } else {
                            Text(
                                text = rev.content,
                                fontSize = 12.sp,
                                fontFamily = FontFamily.Monospace,
                                color = palette.text_primary.toComposeColor()
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(10.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        TextButton(onClick = onDismiss) {
                            Text(trText("关闭"), color = palette.text_secondary.toComposeColor())
                        }
                        Button(
                            onClick = {
                                onRestoreRevision(rev)
                                onDismiss()
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = palette.brand.toComposeColor())
                        ) {
                            Text(trText("恢复到此版本"), color = Color.White, fontSize = 12.sp)
                        }
                    }
                }
            }
        }
        }
    }
}
