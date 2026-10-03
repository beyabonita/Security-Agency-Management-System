const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const edgeFunctionErrors = require(path.resolve(__dirname, '..', 'js', 'edge-function-errors.js'));

function responseContext(payload, requestId, options = {}) {
  const state = { clones: 0 };
  const context = {
    headers: {
      get(name) {
        return String(name).toLowerCase() === 'x-request-id' ? requestId || null : null;
      },
    },
    clone() {
      state.clones += 1;
      return {
        async json() {
          if (options.invalidJson) throw new SyntaxError('Invalid JSON');
          return payload;
        },
      };
    },
  };
  return { context, state };
}

(async () => {
  {
    const { context, state } = responseContext({
      error: 'Use a different IT Admin account to edit your own account.',
      code: 'self_management_blocked',
      requestId: 'req-body-123',
    }, 'req-header-456');
    const result = {
      data: null,
      error: { message: 'Edge Function returned a non-2xx status code', context },
    };
    await assert.rejects(
      () => edgeFunctionErrors.unwrap(result, 'Could not update account.'),
      (error) => {
        assert.equal(
          error.message,
          'Use a different IT Admin account to edit your own account. (Request ID: req-body-123)',
        );
        return true;
      },
    );
    assert.equal(state.clones, 1, 'reads a clone so the original HTTP response remains available');
  }

  {
    const { context } = responseContext({ error: 'That username is already in use.' }, 'req-header-789');
    const message = await edgeFunctionErrors.describe({
      error: { message: 'Edge Function returned a non-2xx status code.', context },
    }, 'Could not create account.');
    assert.equal(message, 'That username is already in use. (Request ID: req-header-789)');
  }

  {
    const { context } = responseContext(null, 'req-fallback-1', { invalidJson: true });
    const message = await edgeFunctionErrors.describe({
      error: { message: 'Edge Function returned a non-2xx status code', context },
    }, 'Could not update account.');
    assert.equal(message, 'Could not update account. (Request ID: req-fallback-1)');
  }

  {
    const message = await edgeFunctionErrors.describe({
      data: { error: 'The account is disabled.', requestId: 'req-data-2' },
      error: null,
    }, 'Could not update account.');
    assert.equal(message, 'The account is disabled. (Request ID: req-data-2)');
  }

  {
    const message = await edgeFunctionErrors.describe({
      data: null,
      error: { message: 'Failed to send a request to the Edge Function', context: null },
    }, 'Could not update account.');
    assert.equal(message, 'Failed to send a request to the Edge Function');
  }

  assert.deepEqual(
    await edgeFunctionErrors.unwrap({ data: { ok: true }, error: null }, 'Could not update account.'),
    { ok: true },
  );

  const usersPage = fs.readFileSync(path.resolve(__dirname, '..', 'it-admin', 'users.html'), 'utf8');
  assert.match(usersPage, /<script src="\.\.\/js\/edge-function-errors\.js"><\/script>/);
  assert.match(usersPage, /person\.id === me\.uid/);
  assert.doesNotMatch(usersPage, /person\.id === me\.id/);
  assert.match(usersPage, /edgeFunctionErrors\.unwrap\(result, 'Could not create account\.'\)/);
  assert.match(usersPage, /edgeFunctionErrors\.unwrap\(result, 'Could not update account\.'\)/);

  console.log('Edge Function error handling checks passed.');
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
