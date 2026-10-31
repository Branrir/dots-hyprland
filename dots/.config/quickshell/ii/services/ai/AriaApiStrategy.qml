import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions as CF

/**
 * Aria (https://github.com/Branrir/aria) as a sidebar model, through its `aria` CLI.
 *
 * Instead of curl, each request runs `aria --json`, which prints one JSON event
 * per line. Aria's backend owns the conversation and the tools, so only the
 * newest user message is sent, and the sidebar's own tools are not offered.
 * Risky tools are asked about with `--confirm-stdin`: a `confirm` event becomes
 * the usual Approve/Reject command block, and the answer is written to the CLI's
 * stdin through a FIFO the request script holds open.
 *
 * Self-contained on purpose: Ai.qml only registers this strategy and forwards
 * function calls and approve/reject to it.
 */
ApiStrategy {
    id: root

    property var ai // The Ai service; set by Ai.qml at creation
    readonly property string modelId: "aria"
    property string ariaBin: "aria"
    property bool supportsConfirmStdin: false

    property bool isReasoning: false
    property string sessionId: ""
    property var lastSentMessage: null
    property string prompt: ""
    property string attachPath: ""
    property var pendingMessage: null
    property int pendingConfirmId: -1
    readonly property string answersFifo: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/quickshell-aria-answers`

    // Find the CLI and whether it can ask over stdin, then offer the model.
    // Offered under policies.ai 1 (yes) and 2 (local): Aria is self-hosted, and
    // the request is a local process, not a call to an online API.
    property Process detect: Process {
        running: Config.ready && Config.options.policies.ai !== 0
        command: ["bash", "-c", `command -v ${root.ariaBin} >/dev/null || exit 1; ${root.ariaBin} --help | grep -q -- --confirm-stdin && echo stdin || echo plain`]
        stdout: StdioCollector {
            onStreamFinished: {
                const mode = text.trim();
                if (mode.length === 0 || !root.ai) return; // No aria on PATH
                root.supportsConfirmStdin = mode === "stdin";
                root.ai.addModel(root.modelId, {
                    "name": "Aria",
                    "icon": "ollama-symbolic",
                    "description": root.supportsConfirmStdin
                        ? Translation.tr("Aria | your local companion, through the aria CLI. Uses Aria's own tools and memory.")
                        : Translation.tr("Aria | your local companion, through the aria CLI.\nThis aria is too old to ask for approval here, so risky tools are refused."),
                    "homepage": "https://github.com/Branrir/aria",
                    "endpoint": "localhost/aria-cli", // "localhost" passes the local-only policy check in Ai.setModel
                    "model": root.modelId,
                    "requires_key": false,
                    "api_format": "aria",
                });
                root.ai.modelList = Object.keys(root.ai.models); // The Ollama loader overwrites the binding
            }
        }
    }

    property Process answerWriter: Process {}

    function newSessionId() { // Same shape as the ids Aria mints itself
        return `s-${Date.now().toString(36)}-${Math.random().toString(36).substr(2, 4)}`;
    }

    function buildEndpoint(model: AiModel): string {
        return ""; // Not used; see finalizeScriptContent
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        const userMessages = messages.filter(m => m.role === "user" && !m.functionName);
        const last = userMessages[userMessages.length - 1];
        // Regenerate resends the same message object: let Aria rewind its own history
        const retry = !!last && last === root.lastSentMessage;
        // A chat that is only this message is a new conversation (fresh sidebar, or after /clear)
        if (!retry && (messages.length <= 1 || root.sessionId.length === 0)) root.sessionId = newSessionId();
        root.prompt = retry ? "/retry" : (last?.rawContent ?? "");
        root.lastSentMessage = last ?? null;
        return {};
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return "";
    }

    function buildScriptFileSetup(filePath) {
        root.attachPath = filePath;
        return "";
    }

    function finalizeScriptContent(scriptContent: string): string {
        const q = s => `'${CF.StringUtils.shellSingleQuoteEscape(s)}'`;
        let args = `--json -s ${q(root.sessionId)}`;
        if (root.attachPath.length > 0 && root.prompt !== "/retry") args += ` -a ${q(root.attachPath)}`;
        root.attachPath = "";
        if (!root.supportsConfirmStdin) {
            return `#!/usr/bin/env bash\nexec ${root.ariaBin} ${args} -- ${q(root.prompt)} </dev/null\n`;
        }
        // Stdin carries the approval answers; the FIFO is held open read-write so neither side blocks
        return "#!/usr/bin/env bash\n"
            + `fifo=${q(root.answersFifo)}\n`
            + 'rm -f "$fifo" && mkfifo -m 600 "$fifo" || exit 1\n'
            + 'exec 3<>"$fifo"\n'
            + `exec ${root.ariaBin} ${args} --confirm-stdin -- ${q(root.prompt)} <&3\n`;
    }

    function append(message, text) {
        message.rawContent += text;
        message.content += text;
    }

    function endReasoning(message) {
        if (!root.isReasoning) return;
        root.isReasoning = false;
        append(message, "\n\n</think>\n\n");
    }

    function parseResponseLine(line, message) {
        let event;
        try {
            event = JSON.parse(line);
        } catch (e) {
            append(message, line);
            return {};
        }
        switch (event.type) {
        case "token":
            endReasoning(message);
            append(message, event.text);
            break;
        case "reasoning":
            if (!root.isReasoning) {
                root.isReasoning = true;
                append(message, "\n\n<think>\n\n");
            }
            append(message, event.text);
            break;
        case "tool":
            endReasoning(message);
            append(message, `\n\n*→ \`${event.name}\`*\n\n`);
            break;
        case "status":
        case "notice":
            endReasoning(message);
            append(message, `\n\n*${event.text}*\n\n`);
            break;
        case "warning":
            endReasoning(message);
            append(message, `\n\n**${event.label}**: ${event.message}\n\n`);
            break;
        case "error":
            endReasoning(message);
            append(message, `\n\n**Error**: ${event.message}`);
            break;
        case "canceled":
            endReasoning(message);
            append(message, `\n\n*${Translation.tr("Canceled")}*`);
            break;
        case "context":
            return { tokenUsage: { input: event.used ?? -1, output: event.out ?? -1, total: (event.used ?? 0) + (event.out ?? 0) } };
        case "confirm":
            endReasoning(message);
            return { functionCall: { name: "aria_confirm", args: { id: event.id, tool: event.tool, what: event.what } } };
        case "confirm_expired":
            if (root.pendingMessage === message && event.id === root.pendingConfirmId) {
                settle(message, event.reason === "canceled" ? Translation.tr("Canceled, declined") : Translation.tr("No answer in time, declined"));
            }
            break;
        }
        return {};
    }

    // Called by Ai.handleFunctionCall; true means handled here
    function handleFunctionCall(name, args, message): bool {
        if (name !== "aria_confirm") return false;
        const what = String(args.what).replace(/```/g, "` ` `");
        append(message, `\n\n**${Translation.tr("Aria wants to use %1").arg(args.tool)}**\n\n\`\`\`command\n${what}\n\`\`\`\n\n`);
        root.pendingMessage = message;
        root.pendingConfirmId = args.id;
        message.functionPending = true;
        return true;
    }

    // Called by Ai.approveCommand/rejectCommand; true means handled here
    function decideFunctionCall(message, approved: bool): bool {
        if (message.functionCall?.name !== "aria_confirm") return false;
        if (!message.functionPending || message !== root.pendingMessage) return true;
        const answer = JSON.stringify({ id: root.pendingConfirmId, approve: approved });
        answerWriter.command = ["timeout", "2", "bash", "-c", 'printf "%s\\n" "$1" > "$2"', "_", answer, root.answersFifo];
        answerWriter.running = true;
        settle(message, approved ? Translation.tr("Approved") : Translation.tr("Declined"));
        return true;
    }

    // Close the open question: no more buttons on this block (a later question in
    // the same message would otherwise light them up again)
    function settle(message, note) {
        message.functionPending = false;
        message.rawContent = message.rawContent.replace(/```command\n/g, "```bash\n");
        message.content = message.content.replace(/```command\n/g, "```bash\n");
        append(message, `*${note}*\n\n`);
        root.pendingMessage = null;
        root.pendingConfirmId = -1;
    }

    function onRequestFinished(message) {
        endReasoning(message);
        if (root.pendingMessage === message) settle(message, Translation.tr("Turn ended before an answer"));
        return {};
    }

    function reset() {
        root.isReasoning = false;
    }
}
