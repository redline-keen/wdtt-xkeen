package com.wdtt.plus

const val DEFAULT_VK_CLIENT_IDS = "6287487,8202606"

val BUILT_IN_VK_CLIENT_IDS: List<String> = DEFAULT_VK_CLIENT_IDS.split(',')

data class CustomVkClientCredentials(
    val enabled: Boolean = false,
    val clientId: String = "",
    val clientSecret: String = ""
) {
    val complete: Boolean
        get() = isValidVkClientId(clientId) && clientSecret.isNotBlank()
}

fun normalizeVkClientId(value: String): String =
    value.filter(Char::isDigit).take(20)

fun normalizeVkClientSecret(value: String): String =
    value.trim().take(512)

fun isValidVkClientId(value: String): Boolean =
    value.isNotBlank() && value.length <= 20 && value.all(Char::isDigit)

fun customVkCredentialsError(credentials: CustomVkClientCredentials): String? = when {
    !credentials.enabled -> null
    !isValidVkClientId(credentials.clientId) -> "Укажите числовой Client ID приложения VK."
    credentials.clientSecret.isBlank() -> "Укажите защищённый ключ (Client secret) приложения VK."
    else -> null
}
