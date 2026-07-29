package com.wdtt.plus.ui

import android.content.pm.PackageManager
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.rememberScrollableState
import androidx.compose.foundation.gestures.scrollable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.graphics.drawable.toBitmap
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.compose.LifecycleResumeEffect
import com.wdtt.plus.isAlwaysBypassedVpnPackage
import com.wdtt.plus.SettingsStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

import androidx.compose.runtime.Stable

@Stable
data class AppItem(
    val name: String,
    val packageName: String,
    val icon: ImageBitmap?,
    val isSystem: Boolean
)

object AppCache {
    var cachedList: List<AppItem>? = null
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExceptionsTab(
    firstVisibleItemIndex: MutableIntState = rememberSaveable { mutableIntStateOf(0) },
    firstVisibleItemScrollOffset: MutableIntState = rememberSaveable { mutableIntStateOf(0) }
) {
    val context = LocalContext.current.applicationContext
    val scope = rememberCoroutineScope()
    val settingsStore = remember { SettingsStore(context) }

    val savedPackages by settingsStore.vpnAppPackages.collectAsStateWithLifecycle(initialValue = "")
    val selectedPackages = remember(savedPackages) {
        savedPackages.split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet()
    }

    var appsList by remember { mutableStateOf<List<AppItem>>(AppCache.cachedList ?: emptyList()) }
    var isLoading by remember { mutableStateOf(AppCache.cachedList == null) }
    var searchQuery by remember { mutableStateOf("") }
    var quickExcludeStatus by rememberSaveable { mutableStateOf("") }
    var reloadJob by remember { mutableStateOf<Job?>(null) }

    fun scheduleWireGuardReload() {
        reloadJob?.cancel()
        reloadJob = scope.launch {
            delay(250)
            com.wdtt.plus.TunnelManager.reloadWireGuard()
        }
    }

    val showSystemAppsOpt by settingsStore.showSystemApps.collectAsStateWithLifecycle(initialValue = null)

    val isWhitelist by settingsStore.isWhitelist.collectAsStateWithLifecycle(initialValue = false)

    // Обновляем список при каждом возвращении в приложение, а кэш используем только
    // для мгновенного первого отображения.
    LifecycleResumeEffect(Unit) {
        val refreshJob = scope.launch {
            if (appsList.isEmpty()) isLoading = true
            val list = withContext(Dispatchers.IO) {
                val loadedApps = mutableListOf<AppItem>()
                val pm = context.packageManager
                val installedApps = pm.getInstalledApplications(PackageManager.GET_META_DATA)

                installedApps.forEach { app ->
                    if (!isAlwaysBypassedVpnPackage(app.packageName, context.packageName)) {
                        val isSys = (app.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                        loadedApps.add(AppItem(
                            name = app.loadLabel(pm).toString(),
                            packageName = app.packageName,
                            icon = app.loadIcon(pm)?.toBitmap()?.asImageBitmap(),
                            isSystem = isSys
                        ))
                    }
                }
                loadedApps.sortedBy { it.name.lowercase() }
            }
            appsList = list
            AppCache.cachedList = appsList
            isLoading = false
        }
        onPauseOrDispose { refreshJob.cancel() }
    }

    val filteredApps by remember {
        derivedStateOf {
            val showSystemApps = showSystemAppsOpt ?: false
            val list = if (showSystemApps) {
                appsList
            } else {
                appsList.filter {
                    !it.isSystem || it.packageName == "com.google.android.youtube" || it.packageName == "com.android.vending"
                }
            }

            if (searchQuery.isBlank()) list
            else list.filter {
                it.name.contains(searchQuery, ignoreCase = true) ||
                it.packageName.contains(searchQuery, ignoreCase = true)
            }
        }
    }

    val listState = rememberRememberedLazyListState(
        firstVisibleItemIndex,
        firstVisibleItemScrollOffset
    )
    var topBlockHeightPx by remember { mutableFloatStateOf(0f) }
    var topBlockOffsetPx by rememberSaveable { mutableStateOf(0f) }
    var topBlockPositionInitialized by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(topBlockHeightPx) {
        if (topBlockHeightPx <= 0f) return@LaunchedEffect
        if (!topBlockPositionInitialized) {
            if (listState.firstVisibleItemIndex > 0 || listState.firstVisibleItemScrollOffset > 0) {
                topBlockOffsetPx = -topBlockHeightPx
            }
            topBlockPositionInitialized = true
        } else {
            topBlockOffsetPx = topBlockOffsetPx.coerceIn(-topBlockHeightPx, 0f)
        }
    }

    fun consumeHeaderScroll(deltaPx: Float, allowExpand: Boolean): Float {
        val previousOffset = topBlockOffsetPx
        val nextOffset = collapsingHeaderOffsetAfterScroll(
            currentOffsetPx = previousOffset,
            headerHeightPx = topBlockHeightPx,
            deltaPx = deltaPx,
            allowExpand = allowExpand,
        )
        if (nextOffset != previousOffset) {
            topBlockOffsetPx = nextOffset
            topBlockPositionInitialized = true
        }
        return nextOffset - previousOffset
    }

    val collapsingHeaderConnection = remember(topBlockHeightPx, listState) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (topBlockHeightPx <= 0f) return Offset.Zero
                val delta = available.y
                val consumed = consumeHeaderScroll(
                    deltaPx = delta,
                    allowExpand = !listState.canScrollBackward,
                )
                return Offset(x = 0f, y = consumed)
            }

            override fun onPostScroll(
                consumed: Offset,
                available: Offset,
                source: NestedScrollSource,
            ): Offset {
                if (available.y <= 0f) return Offset.Zero
                val headerConsumed = consumeHeaderScroll(
                    deltaPx = available.y,
                    allowExpand = true,
                )
                return Offset(x = 0f, y = headerConsumed)
            }
        }
    }
    val searchHeaderScrollState = rememberScrollableState { deltaPx ->
        consumeHeaderScroll(deltaPx = deltaPx, allowExpand = true)
    }
    val collapseFraction = if (topBlockHeightPx > 0f) {
        (-topBlockOffsetPx / topBlockHeightPx).coerceIn(0f, 1f)
    } else {
        0f
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .nestedScroll(collapsingHeaderConnection)
            .padding(horizontal = 16.dp)
    ) {
        CollapsingExceptionsHeader(
            offsetPx = topBlockOffsetPx,
            onHeightChanged = { measuredHeight ->
                if (measuredHeight > 0 && topBlockHeightPx != measuredHeight.toFloat()) {
                    topBlockHeightPx = measuredHeight.toFloat()
                }
            }
        ) {
            Column {
                // Header
                Text(
                    "Маршрутизация приложений",
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.padding(top = 16.dp, bottom = 4.dp)
                )

                Spacer(modifier = Modifier.height(12.dp))

                // Mode Toggle
                AppSectionCard(
                    modifier = Modifier.padding(bottom = 12.dp),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(0.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column(modifier = Modifier.weight(1f).padding(end = 12.dp)) {
                            Text(
                                "Режим списка",
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.Medium,
                                fontSize = 14.sp,
                                color = MaterialTheme.colorScheme.onSurface
                            )
                            Text(
                                if (isWhitelist) "БС: только отмеченные — через VPN"
                                else "ЧС: отмеченные — без VPN",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                fontSize = 11.sp,
                                lineHeight = 14.sp
                            )
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ModeChip("ЧС", !isWhitelist) {
                                if (isWhitelist) {
                                    scope.launch {
                                        settingsStore.saveIsWhitelist(false)
                                        scheduleWireGuardReload()
                                    }
                                }
                            }
                            ModeChip("БС", isWhitelist) {
                                if (!isWhitelist) {
                                    scope.launch {
                                        settingsStore.saveIsWhitelist(true)
                                        scheduleWireGuardReload()
                                    }
                                }
                            }
                        }
                    }

                    HorizontalDivider(
                        modifier = Modifier.padding(vertical = 12.dp),
                        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
                    )

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            "Показывать системные",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium,
                            fontSize = 14.sp,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        Switch(
                            checked = showSystemAppsOpt ?: false,
                            onCheckedChange = { enabled ->
                                scope.launch {
                                    settingsStore.saveShowSystemApps(enabled)
                                }
                            }
                        )
                    }

                    if (!isWhitelist) {
                        Spacer(modifier = Modifier.height(12.dp))
                        OutlinedButton(
                            onClick = {
                                val detectedPackages = appsList
                                    .filter {
                                        matchesQuickExclusionApp(
                                            name = it.name,
                                            packageName = it.packageName,
                                        )
                                    }
                                    .map { it.packageName }
                                    .toSet()
                                if (detectedPackages.isEmpty()) {
                                    quickExcludeStatus = "Подходящие приложения не найдены."
                                } else {
                                    scope.launch {
                                        val addedCount = settingsStore.addBlacklistPackages(detectedPackages)
                                        quickExcludeStatus = "Исключено: ${detectedPackages.size}, добавлено: $addedCount."
                                        scheduleWireGuardReload()
                                    }
                                }
                            },
                            enabled = !isLoading && appsList.isNotEmpty(),
                            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                            shape = RoundedCornerShape(16.dp)
                        ) {
                            Icon(Icons.Default.Search, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text(
                                "Быстрые исключения",
                                fontWeight = FontWeight.SemiBold,
                                textAlign = TextAlign.Center,
                                modifier = Modifier.weight(1f)
                            )
                        }
                        Text(
                            "Приложения из белых списков мобильного интернета и другие сервисы, чувствительные к VPN. Выбираются только найденные на устройстве.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 6.dp)
                        )
                        if (quickExcludeStatus.isNotBlank()) {
                            Text(
                                quickExcludeStatus,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(top = 6.dp)
                            )
                        }
                    }
                }
            }
        }

        // Search Bar
        OutlinedTextField(
            value = searchQuery,
            onValueChange = { searchQuery = it },
            placeholder = { Text("Поиск приложений...", fontSize = 14.sp) },
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 16.dp * collapseFraction, bottom = 12.dp)
                .height(52.dp)
                .scrollable(
                    state = searchHeaderScrollState,
                    orientation = Orientation.Vertical,
                ),
            shape = RoundedCornerShape(16.dp),
            leadingIcon = { Icon(Icons.Default.Search, null, modifier = Modifier.size(20.dp)) },
            singleLine = true,
        )

        // List
        if (isLoading || showSystemAppsOpt == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            if (filteredApps.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        if (searchQuery.isBlank()) "Приложения не найдены" else "По запросу ничего не найдено",
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(filteredApps, key = { it.packageName }) { app ->
                        val isSelected = selectedPackages.contains(app.packageName)

                        AppRow(
                            app = app,
                            isSelected = isSelected,
                            onClick = {
                                scope.launch {
                                    settingsStore.toggleVpnAppSelected(app.packageName, isWhitelist)
                                    scheduleWireGuardReload()
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CollapsingExceptionsHeader(
    offsetPx: Float,
    onHeightChanged: (Int) -> Unit,
    content: @Composable () -> Unit
) {
    Layout(
        modifier = Modifier
            .fillMaxWidth()
            .clipToBounds(),
        content = {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .onSizeChanged { onHeightChanged(it.height) }
            ) {
                content()
            }
        }
    ) { measurables, constraints ->
        val placeable = measurables.single().measure(constraints.copy(minHeight = 0))
        val safeOffset = offsetPx.roundToInt().coerceIn(-placeable.height, 0)
        val visibleHeight = (placeable.height + safeOffset).coerceAtLeast(0)
        layout(placeable.width, visibleHeight) {
            placeable.placeRelative(0, safeOffset)
        }
    }
}

@Composable
private fun ModeChip(label: String, selected: Boolean, onClick: () -> Unit) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = {
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Text(
                    label,
                    fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                    color = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface,
                    textAlign = TextAlign.Center
                )
            }
        },
        modifier = Modifier.width(64.dp),
        shape = RoundedCornerShape(12.dp),
        colors = FilterChipDefaults.filterChipColors(
            selectedContainerColor = MaterialTheme.colorScheme.primary,
            selectedLabelColor = MaterialTheme.colorScheme.onPrimary,
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
            labelColor = MaterialTheme.colorScheme.onSurface
        ),
        border = FilterChipDefaults.filterChipBorder(
            enabled = true,
            selected = selected,
            borderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
            selectedBorderColor = MaterialTheme.colorScheme.primary
        )
    )
}

@Composable
fun AppRow(app: AppItem, isSelected: Boolean, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
        contentColor = MaterialTheme.colorScheme.onSurface,
        tonalElevation = if (isSelected) 4.dp else 0.dp
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (app.icon != null) {
                Image(
                    bitmap = app.icon,
                    contentDescription = null,
                    modifier = Modifier.size(40.dp).clip(RoundedCornerShape(8.dp))
                )
            } else {
                Box(modifier = Modifier.size(40.dp).background(Color.Gray, RoundedCornerShape(8.dp)))
            }

            Spacer(Modifier.width(16.dp))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = app.name,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1
                )
                Text(
                    text = app.packageName,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1
                )
            }

            Checkbox(
                checked = isSelected,
                onCheckedChange = null,
                colors = CheckboxDefaults.colors(checkedColor = MaterialTheme.colorScheme.primary)
            )
        }
    }
}
