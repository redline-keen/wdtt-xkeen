package com.wdtt.plus

internal object DeviceIdentity {
    private val validPattern = Regex("^[A-Za-z0-9_.:-]{8,128}$")
    private val knownInvalidAndroidIds = setOf(
        "9774d56d682e549c",
        "unknown",
    )

    fun valid(value: String): Boolean =
        value.trim().matches(validPattern) &&
            value.trim().lowercase() !in knownInvalidAndroidIds

    fun resolve(
        existing: String?,
        platformId: String?,
        generatedId: String,
    ): String {
        val stored = existing.orEmpty().trim()
        if (valid(stored)) return stored

        val platform = platformId.orEmpty().trim()
        if (valid(platform)) return platform

        val generated = generatedId.trim()
        require(valid(generated)) { "Некорректный резервный идентификатор устройства." }
        return generated
    }
}
