import { passwordError } from "./password-policy.ts";
import cases from "../../tests/password-policy-cases.json" with {
  type: "json",
};

Deno.test("new password policy rejects each missing character class", () => {
  for (const [index, item] of cases.entries()) {
    if ((passwordError(item.password) === null) !== item.valid) {
      throw new Error(`Password policy case ${index} failed`);
    }
  }
  if (passwordError("Aa1!" + "a".repeat(68)) !== null) {
    throw new Error("72-byte passwords should be accepted");
  }
  if (passwordError("Aa1!" + "a".repeat(69)) === null) {
    throw new Error("73-byte passwords should be rejected");
  }
  if (passwordError("Aa1!" + "😀".repeat(18)) === null) {
    throw new Error(
      "Multi-byte passwords exceeding the provider limit must fail",
    );
  }
});
