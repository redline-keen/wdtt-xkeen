package com.wdtt.plus.ui

internal fun collapsingHeaderOffsetAfterScroll(
    currentOffsetPx: Float,
    headerHeightPx: Float,
    deltaPx: Float,
    allowExpand: Boolean,
): Float {
    if (headerHeightPx <= 0f || deltaPx == 0f) return currentOffsetPx
    if (deltaPx > 0f && !allowExpand) return currentOffsetPx
    return (currentOffsetPx + deltaPx).coerceIn(-headerHeightPx, 0f)
}

