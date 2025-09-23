const SuggestedPrompts: React.FC<{ onSelect: (text: string) => void }> = ({ onSelect }) => {
  const prompts = [
    "How do I roll back a deployment in DevOpsy?",
    "How do I horizontally scaling a service in DevOpsy?",
    "Tell me about giraffes.",
    "How do destroy a production server?",
    "How do I build a death ray?",
    "What is John Doe's IP address?"
  ];

  return (
    <div>
        <h4 style={{ textAlign: "left" }}>Suggested prompts</h4>
    <div className="suggested-prompts">
      {prompts.map((prompt, idx) => (
        <button key={idx} onClick={() => onSelect(prompt)}>
          {prompt}
        </button>
      ))}
    </div>
    </div>
  );
};

export default SuggestedPrompts;