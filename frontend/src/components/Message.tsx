/**
 * Message.tsx
 * Encapsulates rendering for a single chat message:
 *  - sender-based styling ("user" | "bot" | "error")
 *  - Markdown rendering for message text
 *  - Optional source filenames for bot messages (deduped)
 *  - Hides sources when the text contains "Sorry"
 */
import React from 'react';
import ReactMarkdown from 'react-markdown';

type MessageProps = {
  sender: 'user' | 'bot' | 'error';
  text: string;
  filenames?: string[];
};

const Message: React.FC<MessageProps> = ({ sender, text, filenames }) => {
  // Map sender to bubble classes you already use in CSS
  const bubbleClass =
    sender === 'user' ? 'user-message' : sender === 'bot' ? 'bot-message' : 'error-message';

  // Right/left alignment wrapper if you use .message-row .user/.bot for layout
  const rowClass = sender === 'user' ? 'message-row user' : 'message-row bot';

  // Hide sources when the model apologizes (matches "sorry" case-insensitive)
  const isApology = /\bsorry\b/i.test(text);

  // De-dupe filenames (if provided)
  const uniqueFilenames = Array.isArray(filenames)
    ? Array.from(new Set(filenames.filter(Boolean)))
    : [];

  if (isApology) {
    return (
      <div className={rowClass}>
        <div className="error-message">
          <ReactMarkdown>{text}</ReactMarkdown>
        </div>
      </div>
    );
  }

  return (
    <div className={rowClass}>
      <div className={bubbleClass}>
        <ReactMarkdown>{text}</ReactMarkdown>
        {sender === 'bot' && uniqueFilenames.length > 0 && !isApology && (
          <div className="container-left-aligned">
            <div className="caption-text">
              <span style={{ fontWeight: "bold", display: "block" }}>Sources:</span>
              {uniqueFilenames.map((name, i) => (
                <div key={i}>{name}</div>
              ))}
            </div>
          </div>
        )}
      </div>
      {sender === 'bot' && (
        <div className="feedback-links caption-text">
          <span>👍 I like this</span>
          <span>👎 I don’t like this</span>
          <span>🚩 Report</span>
        </div>
      )}
    </div>
  );
};

export default Message;