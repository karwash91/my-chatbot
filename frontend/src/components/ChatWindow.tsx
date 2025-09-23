import React, { useState, useEffect, useRef } from "react";
import ReactMarkdown from "react-markdown";
import { API_BASE_URL } from "../utils/config";
import SuggestedPrompts from "./SuggestedPrompts";

type Message = {
    sender: "user" | "bot" | "error";
    text: string;
    filenames?: string[];
};

const ChatWindow: React.FC = () => {
    const [messages, setMessages] = useState<Message[]>([]);
    const [input, setInput] = useState("");
    const [loading, setLoading] = useState(false);
    const messagesEndRef = useRef<HTMLDivElement | null>(null);

    useEffect(() => {
        // Scroll to bottom when messages update
        messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
    }, [messages]);

    const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        setInput(e.target.value);
    };

    const handleSend = async () => {
        const trimmed = input.trim();
        if (!trimmed || loading) return;

        setMessages((prev) => [...prev, { sender: "user", text: trimmed }]);
        setInput("");
        setLoading(true);

        try {
            const response = await fetch(`${API_BASE_URL}/chat`, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                },
                body: JSON.stringify({ query: trimmed }),
            });

            if (!response.ok) {
                const errorText = await response.text();
                console.error("API error response:", errorText);
                throw new Error(`API error: ${response.status} ${response.statusText}`);
            }

            const data = await response.json();
            console.log("API success response:", data);

            if (!data || !data.answer) {
                throw new Error("Invalid response from server.");
            }

            setMessages((prev) => [
                ...prev,
                { sender: "bot", text: data.answer, filenames: data.context?.map((c: any) => c.filename) },
            ]);
        } catch (e: any) {
            console.error("Fetch error:", e);
            setMessages((prev) => [
                ...prev,
                { sender: "error", text: `Error: ${e.message || "Something went wrong."}` },
            ]);
        } finally {
            setLoading(false);
        }
    };

    const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
        if (e.key === "Enter") {
            handleSend();
        }
    };

    return (
        <div className="chat-window">
            <div className="messages">
                {messages.map((msg, idx) => (
                    <div
                        key={idx}
                        className={
                            msg.sender === "user"
                                ? "user-message"
                                : msg.sender === "bot"
                                    ? "bot-message"
                                    : "error-message"
                        }
                    >
                        <ReactMarkdown>{msg.text}</ReactMarkdown>
                        {msg.sender === "bot" && msg.filenames && !msg.text.includes("Sorry") && (
                            <div className="caption-text">
                                <strong>Sources:</strong>
                                <br />
                                {Array.from(new Set(msg.filenames)).map((filename, i) => (
                                    <div key={i}>{filename}</div>
                                ))}
                            </div>
                        )}
                    </div>
                ))}
                {loading && <div className="bot-message thinking-indicator">Thinking...</div>}
                <div ref={messagesEndRef} />
            </div>
            <SuggestedPrompts onSelect={(prompt: string) => setInput(prompt)} />
            <div className="chat-input">
                <input
                    type="text"
                    value={input}
                    onChange={handleInputChange}
                    onKeyDown={handleKeyDown}
                    placeholder="Ask a question..."
                    disabled={loading}
                />
                <button onClick={handleSend} disabled={loading || input.trim() === ""}>
                    Send
                </button>
            </div>
        </div>
    );
};

export default ChatWindow;