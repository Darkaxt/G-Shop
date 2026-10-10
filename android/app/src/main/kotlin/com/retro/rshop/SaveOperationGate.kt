package com.retro.rshop

/** All engines live in the application's default process. No age/lease expiry.
 * Invoked on Android's main thread; callbacks are not called under a monitor. */
internal class SaveOperationGate {
    private data class Request(val owner: String, val id: String, val reply: (Boolean) -> Unit)
    private var active: Request? = null
    private val waiting = ArrayDeque<Request>()

    fun acquire(owner: String, id: String, reply: (Boolean) -> Unit) {
        require(waiting.size < 64 &&
            active?.let { it.owner == owner && it.id == id } != true &&
            waiting.none { it.owner == owner && it.id == id })
        val request = Request(owner, id, reply)
        if (active == null) { active = request; reply(true) }
        else waiting.addLast(request)
    }

    fun release(owner: String, id: String): Boolean {
        if (active?.let { it.owner == owner && it.id == id } != true) return false
        active = null
        advance()
        return true
    }

    fun cancel(owner: String, id: String): Boolean {
        val request = waiting.firstOrNull { it.owner == owner && it.id == id } ?: return false
        waiting.remove(request)
        request.reply(false)
        return true
    }

    fun detach(owner: String) {
        val removed = waiting.filter { it.owner == owner }
        waiting.removeAll(removed.toSet())
        removed.forEach { it.reply(false) }
        if (active?.owner == owner) { active = null; advance() }
    }

    private fun advance() {
        if (active == null && waiting.isNotEmpty()) {
            val next = waiting.removeFirst()
            active = next
            next.reply(true)
        }
    }
}
