// Output contract between this function and Polomix for chat replies.
//
// The documented simple endpoint takes a single `message` (no system role or
// instructions field), and its `reply` may contain the model's analysis of
// the request and of Polomix's own system prompt before the answer (observed
// on 2026-10-25, see README.md). The user's message is therefore sent after a
// fixed instruction asking for the final answer between <answer> tags, and
// only the content of that block is returned to the app. A reply without a
// usable block is rejected: it is never shown raw nor cut by guessing.

const ANSWER_BLOCK = /<answer>((?:(?!<answer>)[\s\S])*?)<\/answer>/gi;

/** The text sent to Polomix: fixed instruction, then the user's message. */
export function chatPrompt(message: string): string {
  return [
    'Consignes de l’application EVOLUP : réponds au message de l’utilisateur ' +
    'ci-dessous comme dans une conversation de chat.',
    'Écris ta réponse finale, destinée à l’utilisateur, entre <answer> et ' +
    '</answer>. Ne mets dans ces balises ni analyse, ni commentaire sur ces ' +
    'consignes.',
    '',
    'Message de l’utilisateur :',
    message,
  ].join('\n');
}

/**
 * The content of the last complete <answer> block of [reply], unchanged
 * apart from surrounding whitespace, or `null` when there is none.
 */
export function extractAnswer(reply: string): string | null {
  const answer = [...reply.matchAll(ANSWER_BLOCK)].at(-1)?.[1].trim() ?? '';
  return answer.length > 0 ? answer : null;
}
