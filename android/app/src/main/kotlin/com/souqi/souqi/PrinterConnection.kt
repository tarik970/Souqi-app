package com.souqi.souqi

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import java.io.IOException
import java.util.UUID

/** A printing failure with the error code the Dart side maps to a message. */
class PrinterException(val code: String, message: String?) : Exception(message)

/**
 * One Bluetooth Classic (RFCOMM / serial port profile) connection to a
 * receipt printer.
 *
 * The socket is kept open between print jobs — reconnecting takes one to two
 * seconds — and is reopened when the address changes or the link turns out
 * to be dead. All methods block: call them from a background thread, never
 * from the main thread. Access is serialised by the caller's single-thread
 * executor.
 */
@SuppressLint("MissingPermission") // The caller checks the runtime permission first.
class PrinterConnection {
    private var socket: BluetoothSocket? = null
    private var address: String? = null

    /**
     * Sends [data] to the printer at [printerAddress] in [chunkSize]-byte pieces with
     * [chunkDelayMs] between them. Cheap printers have a small receive buffer
     * and weak flow control; pacing the stream keeps them from dropping bytes
     * (which shows up as garbage characters or a truncated receipt).
     */
    fun write(
        adapter: BluetoothAdapter,
        printerAddress: String,
        data: ByteArray,
        chunkSize: Int,
        chunkDelayMs: Long,
    ) {
        // Android only accepts MAC addresses with uppercase hex digits.
        val target = printerAddress.trim().uppercase()
        if (!BluetoothAdapter.checkBluetoothAddress(target)) {
            throw PrinterException(UNREACHABLE, "invalid address")
        }
        val reused = isOpenTo(target)
        if (!reused) connect(adapter, target)
        try {
            send(data, chunkSize, chunkDelayMs)
        } catch (e: IOException) {
            close()
            if (!reused) throw PrinterException(WRITE, e.message)
            // The kept-open link was stale (printer switched off and on, or
            // out of range for a while). Reconnect once and send the job
            // again from the start.
            connect(adapter, target)
            try {
                send(data, chunkSize, chunkDelayMs)
            } catch (e2: IOException) {
                close()
                throw PrinterException(WRITE, e2.message)
            }
        }
    }

    fun close() {
        try {
            socket?.close()
        } catch (_: IOException) {
        }
        socket = null
        address = null
    }

    private fun isOpenTo(target: String): Boolean =
        socket?.isConnected == true && address == target

    private fun connect(adapter: BluetoothAdapter, target: String) {
        close()
        val device: BluetoothDevice = adapter.getRemoteDevice(target)
        // A running discovery makes connections slow and unreliable.
        try {
            adapter.cancelDiscovery()
        } catch (_: SecurityException) {
        }

        var lastError: Exception? = null
        // Secure first; some clones only accept the insecure variant.
        for (secure in booleanArrayOf(true, false)) {
            var candidate: BluetoothSocket? = null
            try {
                candidate = if (secure) {
                    device.createRfcommSocketToServiceRecord(SPP_UUID)
                } else {
                    device.createInsecureRfcommSocketToServiceRecord(SPP_UUID)
                }
                candidate.connect()
                socket = candidate
                address = target
                return
            } catch (e: IOException) {
                lastError = e
                try {
                    candidate?.close()
                } catch (_: IOException) {
                }
            }
        }
        throw PrinterException(UNREACHABLE, lastError?.message)
    }

    private fun send(data: ByteArray, chunkSize: Int, chunkDelayMs: Long) {
        val out = socket?.outputStream ?: throw IOException("not connected")
        val size = if (chunkSize > 0) chunkSize else data.size
        var offset = 0
        while (offset < data.size) {
            val count = minOf(size, data.size - offset)
            out.write(data, offset, count)
            out.flush()
            offset += count
            if (chunkDelayMs > 0 && offset < data.size) {
                try {
                    Thread.sleep(chunkDelayMs)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    throw IOException("interrupted")
                }
            }
        }
    }

    companion object {
        /** The standard Serial Port Profile service UUID. */
        private val SPP_UUID: UUID =
            UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

        const val UNREACHABLE = "BT_UNREACHABLE"
        const val WRITE = "BT_WRITE"
    }
}
