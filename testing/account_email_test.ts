import { emailValid } from "../supabase/functions/_shared/accounts.ts";
const actor = "11111111-1111-4111-8111-111111111111",
  target = "22222222-2222-4222-8222-222222222222";
const eq = (a: unknown, b: unknown) => {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw Error(`Expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
  }
};
const handlers: any[] = [];
const serve = Deno.serve;
(Deno as any).serve = (fn: any) => {
  handlers.push(fn);
  return {};
};
await import("../supabase/functions/admin-create-user/index.ts");
await import("../supabase/functions/admin-manage-user/index.ts");
(Deno as any).serve = serve;
Deno.env.set("SUPABASE_URL", "https://example.invalid");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test");
function fixture(o: any = {}) {
  const calls: any[] = [];
  const caller = {
    role: "admin",
    active: true,
    organization_id: "org",
    ...o.caller,
  };
  const profile = {
    id: target,
    role: "user",
    active: true,
    organization_id: "org",
    username: "legacy",
    email: "legacy@asamanion-26858.auth",
    first_name: "Test",
    last_name: "Guard",
    middle_initial: "",
    employment_category: "regular",
    contract_start_date: null,
    contract_end_date: null,
    ...o.profile,
  };
  const result = (data: any, error: any = null) => ({ data, error });
  const client: any = {
    auth: {
      getUser: () => result({ user: { id: actor } }),
      signInWithPassword: () =>
        result({
          user: { id: o.wrongPassword ? target : actor },
          session: o.wrongPassword ? null : {},
        }, o.wrongPassword ? {} : null),
      signOut: () => {
        calls.push(["verificationSignOut"]);
        return {};
      },
      admin: {
        createUser: (data: any) => {
          calls.push(["createAuth", data]);
          return result(
            { user: { id: target } },
            o.authError ? { message: "already registered" } : null,
          );
        },
        deleteUser: () => {
          calls.push(["deleteAuth"]);
          return {};
        },
        getUserById: () =>
          result({ user: { id: profile.id, user_metadata: {} } }),
        updateUserById: (id: any, data: any) => {
          calls.push(["updateAuth", id, data]);
          return result(
            {},
            o.authError ? { message: "already registered" } : null,
          );
        },
      },
    },
    from: (table: string) => {
      let id: any, updating = false, fields: any;
      const value = () => {
        if (table === "organizations") {
          return result({ id: "org", active: true });
        }
        if (updating) {
          return result(
            o.profileError ? null : { id: profile.id },
            o.profileError ? { message: "fail" } : null,
          );
        }
        if (id === actor && !o.self) return result(caller);
        if (id === profile.id) return result(profile);
        return result(o.duplicate ? { id: "duplicate" } : null);
      };
      const q: any = {
        select: () => q,
        eq: (k: string, v: any) => {
          if (k === "id") id = v;
          return q;
        },
        neq: () => q,
        update: (v: any) => {
          updating = true;
          fields = v;
          calls.push(["updateProfile", fields]);
          return q;
        },
        maybeSingle: async () => value(),
        then: (r: any, j: any) => Promise.resolve(value()).then(r, j),
      };
      // Own account is also the caller profile.
      if (o.self) Object.assign(profile, caller, { id: actor });
      return q;
    },
  };
  (globalThis as any).__whiteboxClient = client;
  return { calls, profile };
}
async function run(which: number, body: any, o: any = {}) {
  const f = fixture(o);
  const response = await handlers[which](
    new Request("https://example.invalid", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: "Bearer test",
      },
      body: JSON.stringify(body),
    }),
  );
  return { ...f, status: response.status, body: await response.json() };
}
const create = {
  email: " Guard.Name+post@Gmail.com ",
  password: "Test123!",
  firstName: "Test",
  lastName: "Guard",
  role: "user",
};
Deno.test("email validation accepts real providers and rejects aliases/malformed addresses", () => {
  for (const v of ["a@gmail.com", "a.b+post@company.com.ph"]) {
    eq(emailValid(v), true);
  }
  for (
    const v of [
      "name",
      "a@asamanion-26858.auth",
      "a..b@gmail.com",
      ".a@gmail.com",
      "a.@gmail.com",
      "a@-mail.com",
      "a @gmail.com",
      "a@gmail",
      "a@b@c.com",
    ]
  ) eq(emailValid(v), false);
});
for (const role of ["user", "inspector", "admin", "it_admin"]) {
  Deno.test(
    "create " + role + " with normalized email and same authorized role",
    async () => {
      const r = await run(0, { ...create, role }, {
        caller: {
          role: ["admin", "it_admin"].includes(role) ? "it_admin" : "admin",
        },
      });
      eq(r.status, 200);
      const auth = r.calls.find((c: any) => c[0] === "createAuth")[1];
      eq(auth.email, "guard.name+post@gmail.com");
      eq(auth.password, "Test123!");
      const p = r.calls.find((c: any) => c[0] === "updateProfile")[1];
      eq(p.email, auth.email);
      eq(p.role, role);
    },
  );
}
for (const email of [undefined, "legacy", "a@asamanion-26858.auth"]) {
  Deno.test("creation refuses invalid email " + email, async () => {
    const r = await run(0, { ...create, email });
    eq(r.status, 400);
    eq(r.calls, []);
  });
}
Deno.test("duplicate email rejected before account creation", async () => {
  const r = await run(0, create, { duplicate: true });
  eq(r.status, 409);
  eq(r.calls, []);
});
Deno.test("failed profile creation deletes incomplete Auth account", async () => {
  const r = await run(0, create, { profileError: true });
  eq(r.status, 500);
  eq(r.calls.at(-1)[0], "deleteAuth");
});
Deno.test("email migration retains user ID, internal username and password", async () => {
  const r = await run(1, {
    action: "update",
    userId: target,
    email: " New.Guard@gmail.com ",
  });
  eq(r.status, 200);
  const auth = r.calls.find((c: any) => c[0] === "updateAuth");
  eq(auth[1], target);
  eq(auth[2].email, "new.guard@gmail.com");
  eq(auth[2].password, undefined);
  const p = r.calls.find((c: any) => c[0] === "updateProfile")[1];
  eq(p.username, "legacy");
  eq(p.email, auth[2].email);
});
Deno.test("status/device changes preserve legacy and real login addresses", async () => {
  for (const email of ["legacy@asamanion-26858.auth", "guard@gmail.com"]) {
    const r = await run(
      1,
      { action: "update", userId: target, active: false },
      { profile: { email } },
    );
    eq(r.status, 200);
    eq(r.calls.find((c: any) => c[0] === "updateAuth")[2].email, email);
  }
});
Deno.test("auth failure rolls the profile email back", async () => {
  const r = await run(1, {
    action: "update",
    userId: target,
    email: "guard@gmail.com",
  }, { authError: true });
  eq(r.status, 400);
  eq(r.calls.at(-1)[1].email, "legacy@asamanion-26858.auth");
});
Deno.test("Guard and Inspector cannot create accounts, Operations Head cannot create privileged users", async () => {
  for (const role of ["user", "inspector"]) {
    eq((await run(0, create, { caller: { role } })).status, 403);
  }
  eq((await run(0, { ...create, role: "it_admin" })).status, 403);
  eq(
    (await run(1, {
      action: "update",
      userId: target,
      email: "guard@gmail.com",
    }, { profile: { organization_id: "elsewhere" } })).status,
    403,
  );
});
Deno.test("sole IT Admin can change only own email after password verification", async () => {
  const options = {
    self: true,
    caller: { role: "it_admin", organization_id: null },
    profile: { role: "it_admin" },
  };
  const body = {
    action: "update",
    userId: actor,
    email: "owner@gmail.com",
    currentPassword: "Test123!",
  };
  const r = await run(1, body, options);
  eq(r.status, 200);
  eq(r.calls[0][0], "verificationSignOut");
  eq((await run(1, body, { ...options, wrongPassword: true })).status, 403);
  eq((await run(1, { ...body, currentPassword: "" }, options)).status, 400);
  eq((await run(1, { ...body, active: false }, options)).status, 400);
  eq((await run(1, { ...body, role: "admin" }, options)).status, 400);
});
