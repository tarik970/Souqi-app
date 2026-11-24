package com.souqi.souqi

import androidx.core.content.FileProvider

/**
 * The app's own FileProvider. An empty subclass on purpose: plugins declare
 * their own FileProvider subclasses too, and two <provider> entries with the
 * same class name would fail the manifest merge.
 */
class SouqiFileProvider : FileProvider()
