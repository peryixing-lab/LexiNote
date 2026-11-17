package com.lovexjy.lexinote.ui.pages

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lovexjy.lexinote.core.*
import com.lovexjy.lexinote.ui.components.*
import com.lovexjy.lexinote.ui.theme.LexiAnimatedDialogBox
import com.lovexjy.lexinote.ui.theme.LexiMotion
import com.lovexjy.lexinote.ui.theme.LexiTokens
import com.lovexjy.lexinote.ui.theme.lexiPressScale

@Composable
fun WorkspacesScreen(
    palette: LexiThemePalette,
    onBack: () -> Unit,
    onVaultChanged: () -> Unit
) {
    var refreshTick by remember { mutableIntStateOf(0) }
    var showArchived by remember { mutableStateOf(false) }
    val vaults = remember(refreshTick, showArchived) { LexiStorageService.listVaults(showArchived) }
    val activeVaultId = remember(refreshTick) { LexiStorageService.getActiveVaultId() }
    val projects = remember(refreshTick, activeVaultId) { LexiStorageService.listProjects(activeVaultId) }

    var newVaultName by remember { mutableStateOf("") }
    var newVaultDesc by remember { mutableStateOf("") }
    var newProjectName by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.bg_root.toComposeColor())
    ) {
        LexiBackHeader(
            title = trText("工作区与项目"),
            subtitle = "",
            palette = palette,
            onBack = onBack
        )

        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // Vault List Card
            val vaultCardShape = RoundedCornerShape(20.dp)
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .then(
                        LexiTokens.cardShadow(
                            elevation = LexiTokens.Elev.Level1,
                            shape = vaultCardShape,
                            dark = palette.dark
                        )
                    )
                    .clip(vaultCardShape)
                    .background(palette.surface_card.toComposeColor())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = trText("全部工作区"),
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.text_primary.toComposeColor()
                    )
                    SmallControlChip(
                        text = if (showArchived) trText("隐藏归档") else trText("显示归档"),
                        palette = palette,
                        active = showArchived,
                        onClick = { showArchived = !showArchived }
                    )
                }

                vaults.forEach { v ->
                    val isCurrent = v.id == activeVaultId
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .background(if (isCurrent) palette.brand_soft.toComposeColor() else palette.surface_soft.toComposeColor())
                            .clickable {
                                LexiStorageService.setActiveVaultId(v.id)
                                refreshTick += 1
                                onVaultChanged()
                            }
                            .padding(12.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                LexiIcon(name = "folder", size = 16.dp, palette = palette)
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    text = v.name,
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = if (isCurrent) palette.brand.toComposeColor() else palette.text_primary.toComposeColor()
                                )
                            }
                            if (isCurrent) {
                                Text(
                                    text = trText("当前使用"),
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = palette.brand.toComposeColor()
                                )
                            }
                        }
                        if (v.description.isNotBlank()) {
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                text = v.description,
                                fontSize = 12.sp,
                                color = palette.text_secondary.toComposeColor()
                            )
                        }
                    }
                }

                HorizontalDivider(color = palette.divider.toComposeColor().copy(alpha = 0.6f))
                Text(
                    text = trText("新建工作区"),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                    color = palette.text_primary.toComposeColor()
                )
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(42.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(palette.surface_soft.toComposeColor())
                        .padding(horizontal = 12.dp),
                    contentAlignment = Alignment.CenterStart
                ) {
                    if (newVaultName.isEmpty()) {
                        Text(trText("工作区名称 (如：科研文献库)"), fontSize = 13.sp, color = palette.text_muted.toComposeColor())
                    }
                    BasicTextField(
                        value = newVaultName,
                        onValueChange = { newVaultName = it },
                        singleLine = true,
                        textStyle = TextStyle(color = palette.text_primary.toComposeColor(), fontSize = 14.sp),
                        cursorBrush = SolidColor(palette.brand.toComposeColor()),
                        modifier = Modifier.fillMaxWidth()
                    )
                }
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(42.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(palette.surface_soft.toComposeColor())
                        .padding(horizontal = 12.dp),
                    contentAlignment = Alignment.CenterStart
                ) {
                    if (newVaultDesc.isEmpty()) {
                        Text(trText("简要说明"), fontSize = 13.sp, color = palette.text_muted.toComposeColor())
                    }
                    BasicTextField(
                        value = newVaultDesc,
                        onValueChange = { newVaultDesc = it },
                        singleLine = true,
                        textStyle = TextStyle(color = palette.text_primary.toComposeColor(), fontSize = 14.sp),
                        cursorBrush = SolidColor(palette.brand.toComposeColor()),
                        modifier = Modifier.fillMaxWidth()
                    )
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    SmallControlChip(
                        text = trText("+ 创建并切换工作区"),
                        palette = palette,
                        active = true,
                        onClick = {
                            if (newVaultName.isNotBlank()) {
                                val created = LexiStorageService.createVault(newVaultName.trim(), newVaultDesc.trim())
                                LexiStorageService.setActiveVaultId(created.id)
                                newVaultName = ""
                                newVaultDesc = ""
                                refreshTick += 1
                                onVaultChanged()
                            }
                        }
                    )
                }
            }

            // Projects in Active Vault Card
            val projShape = RoundedCornerShape(20.dp)
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .then(
                        LexiTokens.cardShadow(
                            elevation = LexiTokens.Elev.Level1,
                            shape = projShape,
                            dark = palette.dark
                        )
                    )
                    .clip(projShape)
                    .background(palette.surface_card.toComposeColor())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(
                    text = trText("当前工作区下的项目 / 笔记本"),
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = palette.text_primary.toComposeColor()
                )
                projects.forEach { proj ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(palette.surface_soft.toComposeColor())
                            .padding(horizontal = 12.dp, vertical = 10.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                modifier = Modifier
                                    .size(10.dp)
                                    .clip(CircleShape)
                                    .background(proj.color.toComposeColor())
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = proj.name,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Medium,
                                color = palette.text_primary.toComposeColor()
                            )
                        }
                        if (projects.size > 1) {
                            Text(
                                text = trText("删除"),
                                fontSize = 11.sp,
                                color = palette.danger.toComposeColor(),
                                modifier = Modifier.clickable {
                                    LexiStorageService.deleteProject(proj.id)
                                    refreshTick += 1
                                    onVaultChanged()
                                }
                            )
                        }
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(40.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(palette.surface_soft.toComposeColor())
                            .padding(horizontal = 12.dp),
                        contentAlignment = Alignment.CenterStart
                    ) {
                        if (newProjectName.isEmpty()) {
                            Text(trText("新项目 / 笔记本名称"), fontSize = 13.sp, color = palette.text_muted.toComposeColor())
                        }
                        BasicTextField(
                            value = newProjectName,
                            onValueChange = { newProjectName = it },
                            singleLine = true,
                            textStyle = TextStyle(color = palette.text_primary.toComposeColor(), fontSize = 14.sp),
                            cursorBrush = SolidColor(palette.brand.toComposeColor()),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                    SmallControlChip(
                        text = trText("+ 新增项目"),
                        palette = palette,
                        active = true,
                        onClick = {
                            if (newProjectName.isNotBlank()) {
                                LexiStorageService.createProject(
                                    vaultId = activeVaultId,
                                    name = newProjectName.trim()
                                )
                                newProjectName = ""
                                refreshTick += 1
                                onVaultChanged()
                            }
                        }
                    )
                }
            }
        }
    }
}

@Composable
fun SettingsScreen(
    initialCategory: String = "",
    palette: LexiThemePalette,
    onBack: () -> Unit,
    onSettingsChanged: () -> Unit,
    onReplayGuide: () -> Unit,
    onOpenHelp: () -> Unit
) {
    val context = LocalContext.current
    var activeCategory by remember { mutableStateOf(initialCategory) }
    var searchQuery by remember { mutableStateOf("") }
    var refreshTick by remember { mutableIntStateOf(0) }
    var statusToast by remember { mutableStateOf("") }

    val folderPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocumentTree()
    ) { uri: Uri? ->
        if (uri != null) {
            try {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            } catch (_: Exception) {
            }
            val externalDir = context.getExternalFilesDir(null)
            val targetDir = if (externalDir != null) {
                java.io.File(externalDir, "LexiNoteVault").apply { mkdirs() }.absolutePath
            } else {
                uri.toString()
            }
            LexiStorageService.configureLocalRoot(targetDir)
            statusToast = "已切换本地存储目录并完成全量同步"
            refreshTick += 1
            onSettingsChanged()
        }
    }

    val backupImportLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        if (uri != null) {
            try {
                val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                if (bytes != null) {
                    val name = uri.lastPathSegment?.lowercase() ?: ""
                    val ok = if (name.endsWith(".zip")) {
                        LexiStorageService.importZipArchive(bytes)
                    } else {
                        LexiStorageService.importBackupJson(String(bytes, Charsets.UTF_8))
                    }
                    statusToast = if (ok) "成功导入备份数据" else "备份文件解析失败"
                    refreshTick += 1
                    onSettingsChanged()
                }
            } catch (_: Exception) {
                statusToast = "导入失败"
            }
        }
    }

    val categoryMeta = listOf(
        Triple("appearance", "外观", "主题配色、深浅色模式、强调色与字号"),
        Triple("editor", "编辑器", "默认视图、工具栏档位、行号与拼写检查"),
        Triple("files", "文件与链接", "本地文件夹位置、双链自动更新、快照策略与备份"),
        Triple("plugins", "插件", "安全模式与知萤扩展插件管理"),
        Triple("about", "关于", "版本信息、界面语言切换与新手引导")
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.bg_root.toComposeColor())
    ) {
        val headerTitle = if (activeCategory.isEmpty()) {
            trText("设置")
        } else {
            trText(categoryMeta.firstOrNull { it.first == activeCategory }?.second ?: "设置")
        }

        LexiBackHeader(
            title = headerTitle,
            subtitle = "",
            palette = palette,
            onBack = {
                if (activeCategory.isNotEmpty()) {
                    activeCategory = ""
                } else {
                    onBack()
                }
            }
        )

        if (statusToast.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(palette.brand_soft.toComposeColor())
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = trText(statusToast),
                    fontSize = 12.sp,
                    color = palette.brand.toComposeColor(),
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "×",
                    fontSize = 14.sp,
                    color = palette.brand.toComposeColor(),
                    modifier = Modifier.clickable { statusToast = "" }
                )
            }
        }

        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            LexiMotion.RouteContent(
                targetState = activeCategory,
                isForward = { old, new -> old.isEmpty() && new.isNotEmpty() }
            ) { currentCategory ->
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (currentCategory.isEmpty()) {
                // Phone Root Category List (matches LexiSettingsWindow.ets)
                Text(
                    text = trText("选项"),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    color = palette.text_secondary.toComposeColor(),
                    modifier = Modifier.padding(horizontal = 4.dp)
                )

                val groupShape = RoundedCornerShape(20.dp)
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(
                            LexiTokens.cardShadow(
                                elevation = LexiTokens.Elev.Level1,
                                shape = groupShape,
                                dark = palette.dark
                            )
                        )
                        .clip(groupShape)
                        .background(palette.surface_card.toComposeColor())
                ) {
                    val optionRows = listOf(
                        Triple("appearance", "sun", "外观"),
                        Triple("editor", "note", "编辑器"),
                        Triple("files", "folder", "文件与链接"),
                        Triple("plugins", "plugin", "插件")
                    )
                    optionRows.forEachIndexed { idx, (id, icon, label) ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(56.dp)
                                .clickable { activeCategory = id }
                                .padding(horizontal = 16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(
                                    modifier = Modifier
                                        .size(34.dp)
                                        .clip(RoundedCornerShape(10.dp))
                                        .background(palette.brand_soft.toComposeColor()),
                                    contentAlignment = Alignment.Center
                                ) {
                                    LexiIcon(name = icon, size = 18.dp, palette = palette)
                                }
                                Spacer(modifier = Modifier.width(12.dp))
                                Text(
                                    text = trText(label),
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.Medium,
                                    color = palette.text_primary.toComposeColor()
                                )
                            }
                            LexiIcon(name = "chevron", size = 15.dp, muted = true, palette = palette)
                        }
                        if (idx < optionRows.lastIndex) {
                            HorizontalDivider(
                                modifier = Modifier.padding(start = 62.dp),
                                thickness = 0.5.dp,
                                color = palette.divider.toComposeColor().copy(alpha = 0.65f)
                            )
                        }
                    }
                }

                val aboutShape = RoundedCornerShape(20.dp)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(54.dp)
                        .then(
                            LexiTokens.cardShadow(
                                elevation = LexiTokens.Elev.Level1,
                                shape = aboutShape,
                                dark = palette.dark
                            )
                        )
                        .clip(aboutShape)
                        .background(palette.surface_card.toComposeColor())
                        .clickable { activeCategory = "about" }
                        .padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = trText("关于"),
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Medium,
                        color = palette.text_primary.toComposeColor()
                    )
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            text = "2.0.1",
                            fontSize = 13.sp,
                            color = palette.text_muted.toComposeColor()
                        )
                        LexiIcon(name = "chevron", size = 15.dp, muted = true, palette = palette)
                    }
                }
            } else {
                when (currentCategory) {
                    "appearance" -> {
                        val currentThemeId = remember(refreshTick) { LexiStorageService.getThemeId() }
                        val colorMode = remember(refreshTick) { LexiStorageService.getColorMode() }
                        val accentColor = remember(refreshTick) { LexiStorageService.getAccentColor() }

                        SettingsCard(title = "色彩模式", palette = palette) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                listOf(
                                    "system" to "跟随系统",
                                    "light" to "浅色模式",
                                    "dark" to "深色模式"
                                ).forEach { (mode, label) ->
                                    SmallControlChip(
                                        text = trText(label),
                                        palette = palette,
                                        active = colorMode == mode,
                                        onClick = {
                                            LexiStorageService.setColorMode(mode)
                                            refreshTick += 1
                                            onSettingsChanged()
                                        }
                                    )
                                }
                            }
                        }

                        SettingsCard(title = "精选主题预设", palette = palette) {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                LexiTheme.PRESETS.forEach { preset ->
                                    val active = preset.id == currentThemeId
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clip(RoundedCornerShape(14.dp))
                                            .background(if (active) palette.brand_soft.toComposeColor() else palette.surface_soft.toComposeColor())
                                            .clickable {
                                                LexiStorageService.setThemeId(preset.id)
                                                refreshTick += 1
                                                onSettingsChanged()
                                            }
                                            .padding(12.dp),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Column {
                                            Text(
                                                text = trText(preset.name),
                                                fontSize = 14.sp,
                                                fontWeight = FontWeight.Bold,
                                                color = palette.text_primary.toComposeColor()
                                            )
                                            Text(
                                                text = trText(preset.subtitle),
                                                fontSize = 11.sp,
                                                color = palette.text_muted.toComposeColor()
                                            )
                                        }
                                        Box(
                                            modifier = Modifier
                                                .size(22.dp)
                                                .clip(CircleShape)
                                                .background(preset.light.brand.toComposeColor())
                                        )
                                    }
                                }
                            }
                        }

                        SettingsCard(title = "自定义强调色", palette = palette) {
                            val accents = listOf(
                                "" to "跟随主题",
                                "#6E44D9" to "知萤紫",
                                "#2B6CB0" to "晴空蓝",
                                "#2F855A" to "松林绿",
                                "#B76524" to "琥珀橙",
                                "#B83280" to "暮光粉"
                            )
                            Row(
                                modifier = Modifier.horizontalScroll(rememberScrollState()),
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                accents.forEach { (hex, label) ->
                                    SmallControlChip(
                                        text = trText(label),
                                        palette = palette,
                                        active = accentColor.equals(hex, ignoreCase = true),
                                        onClick = {
                                            LexiStorageService.setAccentColor(hex)
                                            refreshTick += 1
                                            onSettingsChanged()
                                        }
                                    )
                                }
                            }
                        }
                    }

                    "editor" -> {
                        val defaultView = remember(refreshTick) { LexiStorageService.getDefaultEditorViewMode() }
                        val toolbarMode = remember(refreshTick) { LexiStorageService.getNoteToolbarMode() }
                        val fontSize = remember(refreshTick) { LexiStorageService.getEditorFontSize() }
                        val lineNumbers = remember(refreshTick) { LexiStorageService.getEditorShowLineNumbers() }
                        val readableWidth = remember(refreshTick) { LexiStorageService.getEditorReadableLineLength() }
                        val spellcheck = remember(refreshTick) { LexiStorageService.getEditorSpellcheck() }

                        SettingsCard(title = "默认打开视图", palette = palette) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                listOf(
                                    "live" to "实时预览",
                                    "reading" to "沉浸阅读",
                                    "source" to "源码模式"
                                ).forEach { (m, label) ->
                                    SmallControlChip(
                                        text = trText(label),
                                        palette = palette,
                                        active = defaultView == m,
                                        onClick = {
                                            LexiStorageService.setDefaultEditorViewMode(m)
                                            refreshTick += 1
                                            onSettingsChanged()
                                        }
                                    )
                                }
                            }
                        }

                        SettingsCard(title = "手机工具栏默认档位", palette = palette) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                listOf(
                                    "minimal" to "简洁",
                                    "study" to "学习",
                                    "pro" to "专业"
                                ).forEach { (t, label) ->
                                    SmallControlChip(
                                        text = trText(label),
                                        palette = palette,
                                        active = toolbarMode == t,
                                        onClick = {
                                            LexiStorageService.setNoteToolbarMode(t)
                                            refreshTick += 1
                                            onSettingsChanged()
                                        }
                                    )
                                }
                            }
                        }

                        SettingsCard(title = "正文字号 ($fontSize px)", palette = palette) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                listOf(14, 16, 18, 20).forEach { sz ->
                                    SmallControlChip(
                                        text = "${sz}px",
                                        palette = palette,
                                        active = fontSize == sz,
                                        onClick = {
                                            LexiStorageService.setEditorFontSize(sz)
                                            refreshTick += 1
                                            onSettingsChanged()
                                        }
                                    )
                                }
                            }
                        }

                        SettingsCard(title = "编辑器行为偏好", palette = palette) {
                            SettingsSwitchRow(
                                label = "代码块默认显示行号",
                                checked = lineNumbers,
                                palette = palette,
                                onCheckedChange = {
                                    LexiStorageService.setEditorShowLineNumbers(it)
                                    refreshTick += 1
                                }
                            )
                            SettingsSwitchRow(
                                label = "缩窄阅读行宽（提升专注度）",
                                checked = readableWidth,
                                palette = palette,
                                onCheckedChange = {
                                    LexiStorageService.setEditorReadableLineLength(it)
                                    refreshTick += 1
                                }
                            )
                            SettingsSwitchRow(
                                label = "拼写与语法辅助提示",
                                checked = spellcheck,
                                palette = palette,
                                onCheckedChange = {
                                    LexiStorageService.setEditorSpellcheck(it)
                                    refreshTick += 1
                                }
                            )
                        }
                    }

                    "files" -> {
                        val locStatus = remember(refreshTick) { LexiStorageService.storageLocationStatus() }
                        val autoUpdateLinks = remember(refreshTick) { LexiStorageService.getAutoUpdateLinks() }
                        val historySummary = remember(refreshTick) { LexiStorageService.getHistoryUsageSummary() }

                        SettingsCard(title = "本地存储位置", palette = palette) {
                            Text(
                                text = trText(locStatus.title),
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold,
                                color = palette.text_primary.toComposeColor()
                            )
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                text = locStatus.path,
                                fontSize = 11.sp,
                                fontFamily = FontFamily.Monospace,
                                color = palette.brand.toComposeColor()
                            )
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                text = trText(locStatus.description),
                                fontSize = 12.sp,
                                color = palette.text_secondary.toComposeColor()
                            )
                            Spacer(modifier = Modifier.height(10.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                SmallControlChip(
                                    text = trText("选择本地位置"),
                                    palette = palette,
                                    active = true,
                                    onClick = { folderPickerLauncher.launch(null) }
                                )
                                if (locStatus.mode == "custom") {
                                    SmallControlChip(
                                        text = trText("恢复内部存储"),
                                        palette = palette,
                                        onClick = {
                                            LexiStorageService.resetToInternalStorage()
                                            statusToast = "已恢复为应用内部安全存储"
                                            refreshTick += 1
                                            onSettingsChanged()
                                        }
                                    )
                                }
                            }
                        }

                        SettingsCard(title = "链接与历史快照", palette = palette) {
                            SettingsSwitchRow(
                                label = "重命名笔记标题时自动更新所有 [[双链]]",
                                checked = autoUpdateLinks,
                                palette = palette,
                                onCheckedChange = {
                                    LexiStorageService.setAutoUpdateLinks(it)
                                    refreshTick += 1
                                }
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                text = "历史快照占用: ${LexiNoteHistory.formatBytes(historySummary.totalBytes)} (${historySummary.totalRevisions} 个版本)",
                                fontSize = 12.sp,
                                color = palette.text_secondary.toComposeColor()
                            )
                            Spacer(modifier = Modifier.height(6.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                SmallControlChip(
                                    text = trText("清理冗余快照"),
                                    palette = palette,
                                    onClick = {
                                        val res = LexiStorageService.pruneAllNoteHistories()
                                        statusToast = "已清理 ${res.removedCount} 个旧版本"
                                        refreshTick += 1
                                    }
                                )
                                SmallControlChip(
                                    text = trText("重建知识库索引"),
                                    palette = palette,
                                    onClick = {
                                        val count = LexiStorageService.rebuildIndex()
                                        statusToast = "已重建 $count 条双向链接索引"
                                        refreshTick += 1
                                        onSettingsChanged()
                                    }
                                )
                            }
                        }

                        SettingsCard(title = "备份导入与导出", palette = palette) {
                            Row(
                                modifier = Modifier.horizontalScroll(rememberScrollState()),
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                SmallControlChip(
                                    text = trText("导入 JSON / ZIP 备份"),
                                    palette = palette,
                                    active = true,
                                    onClick = { backupImportLauncher.launch("*/*") }
                                )
                                SmallControlChip(
                                    text = trText("同步当前全量数据到本地目录"),
                                    palette = palette,
                                    onClick = {
                                        val ok = LexiStorageService.syncSnapshotToLocalRoot()
                                        statusToast = if (ok) "已同步全量 Markdown 与 JSON 到存储目录" else "请先选择本地目录"
                                    }
                                )
                            }
                        }
                    }

                    "plugins" -> {
                        val safeMode = remember(refreshTick) { LexiStorageService.getPluginSafeMode() }
                        val plugins = remember(refreshTick) { LexiStorageService.listPlugins() }

                        SettingsCard(title = "安全模式", palette = palette) {
                            SettingsSwitchRow(
                                label = "启用安全模式（暂停第三方插件命令）",
                                checked = safeMode,
                                palette = palette,
                                onCheckedChange = {
                                    LexiStorageService.setPluginSafeMode(it)
                                    refreshTick += 1
                                }
                            )
                        }

                        SettingsCard(title = "已安装插件 (${plugins.size})", palette = palette) {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                plugins.forEach { p ->
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clip(RoundedCornerShape(14.dp))
                                            .background(palette.surface_soft.toComposeColor())
                                            .padding(12.dp),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Column(modifier = Modifier.weight(1f)) {
                                            Text(
                                                text = "${trText(p.name)} (v${p.version})",
                                                fontSize = 14.sp,
                                                fontWeight = FontWeight.Bold,
                                                color = palette.text_primary.toComposeColor()
                                            )
                                            Text(
                                                text = trText(p.description),
                                                fontSize = 11.sp,
                                                color = palette.text_secondary.toComposeColor()
                                            )
                                        }
                                        Switch(
                                            checked = p.enabled,
                                            onCheckedChange = { enabled ->
                                                LexiStorageService.setPluginEnabled(p.id, enabled)
                                                refreshTick += 1
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }

                    "about" -> {
                        val currentLang = remember(refreshTick) { LexiStorageService.getAppLanguage() }

                        SettingsCard(title = "知萤 LexiNote", palette = palette) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                LexiLogo(size = 44.dp)
                                Spacer(modifier = Modifier.width(12.dp))
                                Column {
                                    Text(
                                        text = "知萤 LexiNote v1.2.0",
                                        fontSize = 16.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = palette.text_primary.toComposeColor()
                                    )
                                    Text(
                                        text = trText("Android 与 HarmonyOS 手机双端体验一致版"),
                                        fontSize = 12.sp,
                                        color = palette.text_secondary.toComposeColor()
                                    )
                                }
                            }
                        }

                        SettingsCard(title = "界面语言 / Language", palette = palette) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                SmallControlChip(
                                    text = "简体中文",
                                    palette = palette,
                                    active = currentLang == "zh",
                                    onClick = {
                                        LexiStorageService.setAppLanguage("zh")
                                        refreshTick += 1
                                        onSettingsChanged()
                                    }
                                )
                                SmallControlChip(
                                    text = "English",
                                    palette = palette,
                                    active = currentLang == "en",
                                    onClick = {
                                        LexiStorageService.setAppLanguage("en")
                                        refreshTick += 1
                                        onSettingsChanged()
                                    }
                                )
                            }
                        }

                        SettingsCard(title = "引导与帮助", palette = palette) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                SmallControlChip(
                                    text = trText("重播欢迎引导"),
                                    palette = palette,
                                    active = true,
                                    onClick = onReplayGuide
                                )
                                SmallControlChip(
                                    text = trText("查看使用指南"),
                                    palette = palette,
                                    onClick = onOpenHelp
                                )
                            }
                        }
                    }
                }
            }
            }
            }
        }
    }
}

@Composable
private fun SettingsCategoryRow(
    title: String,
    subtitle: String,
    palette: LexiThemePalette,
    onClick: () -> Unit
) {
    val interaction = LexiMotion.rememberInteraction()
    val cardShape = RoundedCornerShape(LexiTokens.Radius.Card)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .lexiPressScale(interaction)
            .then(
                LexiTokens.cardShadow(
                    elevation = LexiTokens.Elev.Level1,
                    shape = cardShape,
                    dark = palette.dark
                )
            )
            .clip(cardShape)
            .background(palette.surface_card.toComposeColor())
            .border(LexiTokens.Border.Hairline, palette.stroke.toComposeColor(), cardShape)
            .then(LexiMotion.clickTarget(interaction) { onClick() })
            .padding(14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = trText(title),
                style = LexiTokens.Type.Body,
                fontWeight = FontWeight.SemiBold,
                color = palette.text_primary.toComposeColor()
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = trText(subtitle),
                style = LexiTokens.Type.Caption,
                color = palette.text_muted.toComposeColor()
            )
        }
        LexiIcon(name = "chevron", size = 16.dp, muted = true, palette = palette)
    }
}

@Composable
private fun SettingsCard(
    title: String,
    palette: LexiThemePalette,
    content: @Composable ColumnScope.() -> Unit
) {
    val cardShape = RoundedCornerShape(20.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                LexiTokens.cardShadow(
                    elevation = LexiTokens.Elev.Level1,
                    shape = cardShape,
                    dark = palette.dark
                )
            )
            .clip(cardShape)
            .background(palette.surface_card.toComposeColor())
            .padding(16.dp)
    ) {
        Text(
            text = trText(title),
            style = LexiTokens.Type.H3,
            color = palette.text_primary.toComposeColor()
        )
        Spacer(modifier = Modifier.height(10.dp))
        content()
    }
}

@Composable
private fun SettingsSwitchRow(
    label: String,
    checked: Boolean,
    palette: LexiThemePalette,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = trText(label),
            fontSize = 13.sp,
            color = palette.text_primary.toComposeColor(),
            modifier = Modifier.weight(1f)
        )
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange
        )
    }
}

@Composable
fun TrashScreen(
    palette: LexiThemePalette,
    onBack: () -> Unit,
    onChanged: () -> Unit
) {
    var refreshTick by remember { mutableIntStateOf(0) }
    val activeVaultId = remember { LexiStorageService.getActiveVaultId() }
    val deletedNotes = remember(refreshTick) { LexiStorageService.listDeletedNotes(activeVaultId) }
    val deletedMindMaps = remember(refreshTick) { LexiStorageService.listDeletedMindMaps(activeVaultId) }
    val deletedCanvases = remember(refreshTick) { LexiStorageService.listDeletedCanvases(activeVaultId) }
    val totalDeleted = deletedNotes.size + deletedMindMaps.size + deletedCanvases.size

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.bg_root.toComposeColor())
    ) {
        LexiBackHeader(
            title = trText("回收站"),
            subtitle = "$totalDeleted ${trText("项已删除内容")}",
            rightText = if (totalDeleted > 0) trText("清空") else "",
            palette = palette,
            onBack = onBack,
            onRightAction = if (totalDeleted > 0) {
                {
                    LexiStorageService.emptyTrash(activeVaultId)
                    refreshTick += 1
                    onChanged()
                }
            } else null
        )

        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (totalDeleted == 0) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 48.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = trText("回收站为空"),
                        fontSize = 14.sp,
                        color = palette.text_muted.toComposeColor()
                    )
                }
            }

            deletedNotes.forEach { note ->
                TrashItemRow(
                    icon = "note",
                    title = note.title,
                    subtitle = "${trText("笔记")} · ${formatTimeShort(note.deletedAt)}",
                    palette = palette,
                    onRestore = {
                        LexiStorageService.restoreNote(note.id)
                        refreshTick += 1
                        onChanged()
                    },
                    onPurge = {
                        LexiStorageService.purgeNote(note.id)
                        refreshTick += 1
                        onChanged()
                    }
                )
            }

            deletedMindMaps.forEach { mm ->
                TrashItemRow(
                    icon = "mindmap",
                    title = mm.title,
                    subtitle = "${trText("思维导图")} · ${formatTimeShort(mm.deletedAt)}",
                    palette = palette,
                    onRestore = {
                        LexiStorageService.restoreMindMap(mm.id)
                        refreshTick += 1
                        onChanged()
                    },
                    onPurge = {
                        LexiStorageService.purgeMindMap(mm.id)
                        refreshTick += 1
                        onChanged()
                    }
                )
            }

            deletedCanvases.forEach { cv ->
                TrashItemRow(
                    icon = "canvas",
                    title = cv.title,
                    subtitle = "${trText("自由白板")} · ${formatTimeShort(cv.deletedAt)}",
                    palette = palette,
                    onRestore = {
                        LexiStorageService.restoreCanvas(cv.id)
                        refreshTick += 1
                        onChanged()
                    },
                    onPurge = {
                        LexiStorageService.purgeCanvas(cv.id)
                        refreshTick += 1
                        onChanged()
                    }
                )
            }
        }
    }
}

@Composable
private fun TrashItemRow(
    icon: String,
    title: String,
    subtitle: String,
    palette: LexiThemePalette,
    onRestore: () -> Unit,
    onPurge: () -> Unit
) {
    val cardShape = RoundedCornerShape(18.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                LexiTokens.cardShadow(
                    elevation = LexiTokens.Elev.Level1,
                    shape = cardShape,
                    dark = palette.dark
                )
            )
            .clip(cardShape)
            .background(palette.surface_card.toComposeColor())
            .padding(14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.weight(1f)
        ) {
            LexiIcon(name = icon, size = 18.dp, palette = palette)
            Spacer(modifier = Modifier.width(10.dp))
            Column {
                Text(
                    text = title,
                    style = LexiTokens.Type.BodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = palette.text_primary.toComposeColor()
                )
                Text(
                    text = subtitle,
                    style = LexiTokens.Type.TnumMicro,
                    color = palette.text_muted.toComposeColor()
                )
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            SmallControlChip(
                text = trText("恢复"),
                palette = palette,
                active = true,
                onClick = onRestore
            )
            SmallControlChip(
                text = trText("彻底删除"),
                palette = palette,
                onClick = onPurge
            )
        }
    }
}

@Composable
fun HelpScreen(
    palette: LexiThemePalette,
    onBack: () -> Unit
) {
    val guides = remember {
        listOf(
            "1. 双向链接与章节引用" to "在正文中输入 [[笔记标题]] 或 [[笔记标题#章节名|显示别名]] 即可建立双向知识连接。在底部面板与探索页可实时查看反向引用。",
            "2. 多级标签体系" to "支持 #标签 与 #学科/数学/线性代数 多级标签语法，点击标签即可在知识库中聚合筛选。",
            "3. LaTeX 数学公式渲染" to "支持 \$a^2+b^2=c^2\$ 行内公式与 \$\$...\\tag{1}\$\$ 多行公式块，内置可读符号美化与未闭合提示。",
            "4. YAML Frontmatter 属性" to "支持文件头部 --- 属性块与底部可视化属性面板双向同步，并可通过 prop:key=val 语法精准检索。",
            "5. 思维导图与 Markdown 互转" to "导图支持向右、双向、组织结构三种布局，可一键将笔记标题大纲转换为思维导图，或将导图导出为大纲笔记。",
            "6. 自由白板二维思考" to "在白板中自由拖拽卡片、建立带标签的连线，并将卡片与知识库中的具体笔记深度绑定。",
            "7. 版本历史与差异对比" to "每次保存自动维护历史快照，支持逐行 + / - 差异对比与一键回滚。",
            "8. 离线语音与本地整理助手" to "无需联网即可提取笔记核心摘要、行动待办清单、推荐双链与建议标签。",
            "9. 模板引擎与今日笔记" to "内置每日笔记、康奈尔笔记、读书笔记、项目复盘等 6 套模板，支持 {{date}}、{{time}} 动态替换。",
            "10. 本地优先与开放格式" to "所有笔记均可直接同步为本地文件夹中的标准 .md 文件，并支持 JSON 与 ZIP 完整备份导入导出。"
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.bg_root.toComposeColor())
    ) {
        LexiBackHeader(
            title = trText("使用指南"),
            subtitle = trText("知萤 LexiNote 核心功能速览"),
            palette = palette,
            onBack = onBack
        )

        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            guides.forEach { (title, body) ->
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .background(palette.surface_card.toComposeColor())
                        .border(1.dp, palette.stroke.toComposeColor(), RoundedCornerShape(16.dp))
                        .padding(14.dp)
                ) {
                    Text(
                        text = trText(title),
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = palette.brand.toComposeColor()
                    )
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        text = trText(body),
                        fontSize = 13.sp,
                        color = palette.text_secondary.toComposeColor(),
                        lineHeight = 19.sp
                    )
                }
            }
        }
    }
}

@Composable
fun ShareCaptureScreen(
    initialDraft: LexiShareDraft?,
    palette: LexiThemePalette,
    onBack: () -> Unit,
    onSavedToNote: (NoteItem) -> Unit
) {
    var title by remember(initialDraft) {
        mutableStateOf(initialDraft?.title?.ifBlank { "分享摘录 ${LexiTemplates.dateKey()}" } ?: "分享摘录 ${LexiTemplates.dateKey()}")
    }
    var text by remember(initialDraft) { mutableStateOf(initialDraft?.text ?: "") }
    var url by remember(initialDraft) { mutableStateOf(initialDraft?.url ?: "") }
    val vaults = remember { LexiStorageService.listVaults(false) }
    var selectedVaultId by remember {
        mutableStateOf(LexiStorageService.getActiveVaultId().ifEmpty { vaults.firstOrNull()?.id ?: "vault_default" })
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.bg_root.toComposeColor())
    ) {
        LexiBackHeader(
            title = trText("知萤收件箱"),
            subtitle = trText("快速剪藏外部文本或链接到知识库"),
            rightText = trText("保存"),
            palette = palette,
            onBack = onBack,
            onRightAction = {
                val md = buildString {
                    append("# $title\n\n")
                    if (url.isNotBlank()) {
                        append("> 来源链接: $url\n\n")
                    }
                    append(text.trim())
                    append("\n")
                }
                val created = LexiStorageService.createNote(
                    title = title,
                    content = md,
                    tags = listOf("剪藏", "收件箱"),
                    vaultId = selectedVaultId
                )
                onSavedToNote(created)
            }
        )

        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(20.dp))
                    .background(palette.surface_card.toComposeColor())
                    .border(1.dp, palette.stroke.toComposeColor(), RoundedCornerShape(20.dp))
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                OutlinedTextField(
                    value = title,
                    onValueChange = { title = it },
                    label = { Text(trText("笔记标题")) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = url,
                    onValueChange = { url = it },
                    label = { Text(trText("来源链接 (可选)")) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    label = { Text(trText("剪藏正文内容")) },
                    minLines = 6,
                    maxLines = 12,
                    modifier = Modifier.fillMaxWidth()
                )

                Text(
                    text = trText("保存到工作区："),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = palette.text_secondary.toComposeColor()
                )
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    vaults.forEach { v ->
                        SmallControlChip(
                            text = v.name,
                            palette = palette,
                            active = v.id == selectedVaultId,
                            onClick = { selectedVaultId = v.id }
                        )
                    }
                }
            }
        }
    }
}
