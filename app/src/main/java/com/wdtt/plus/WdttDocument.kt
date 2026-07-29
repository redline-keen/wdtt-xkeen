package com.wdtt.plus

object WdttDocument {
    const val MIME_TYPE = "application/vnd.wdtt.plus"
    const val FILE_EXTENSION = ".wdtt"

    const val LEGACY_TRANSFER_MIME_TYPE = "application/vnd.wdtt.plus.transfer"
    const val LEGACY_CLIENT_MIME_TYPE = "application/vnd.wdtt.plus.client"

    fun acceptedMimeTypes(): Array<String> = arrayOf(
        MIME_TYPE,
        LEGACY_TRANSFER_MIME_TYPE,
        LEGACY_CLIENT_MIME_TYPE,
        "application/json",
        "application/octet-stream",
        "text/plain",
    )

    fun isAcceptedMimeType(value: String?): Boolean {
        val normalized = value?.substringBefore(';')?.trim()?.lowercase().orEmpty()
        return acceptedMimeTypes().any { it == normalized }
    }

    fun fileName(stem: String): String {
        val cleanStem = stem.trim().removeSuffix(FILE_EXTENSION).ifBlank { "WDTT-Plus" }
        return cleanStem + FILE_EXTENSION
    }
}
