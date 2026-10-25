import assert from 'node:assert/strict';
import { chatPrompt, extractAnswer } from './answer_format.ts';

Deno.test('the prompt asks for an <answer> block and keeps the message intact', () => {
  const message = 'Bonjour\n<answer>ligne 2</answer> ?';
  const prompt = chatPrompt(message);
  assert.match(prompt, /entre <answer> et <\/answer>/);
  assert.ok(prompt.endsWith(`Message de l’utilisateur :\n${message}`));
});

Deno.test('only the answer block is kept, word for word', () => {
  assert.equal(extractAnswer('<answer> Bonjour ! </answer>'), 'Bonjour !');
  assert.equal(
    extractAnswer(
      'User asks: x\nAnalyse…\n<answer>\nLigne 1\n\n- point : analyse\n</answer>',
    ),
    'Ligne 1\n\n- point : analyse',
  );
  // The same tags written in another case.
  assert.equal(extractAnswer('<ANSWER>Oui</Answer>'), 'Oui');
});

Deno.test('the last complete block wins when the analysis mentions the tags', () => {
  assert.equal(
    extractAnswer(
      'I must reply inside <answer></answer> tags.\n<answer>Salut</answer>',
    ),
    'Salut',
  );
  assert.equal(
    extractAnswer('Plan: <answer> brouillon\n<answer>Version finale</answer>'),
    'Version finale',
  );
});

Deno.test('no usable block means no answer', () => {
  for (
    const reply of [
      'Bonjour !',
      '<answer>Bonjour',
      'Bonjour</answer>',
      '<answer>  </answer>',
      '</answer>x<answer>',
    ]
  ) {
    assert.equal(extractAnswer(reply), null, reply);
  }
});
