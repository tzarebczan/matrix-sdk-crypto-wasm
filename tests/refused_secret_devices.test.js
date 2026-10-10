// Fork: the owner's list of own devices refused secrets and forwarded room
// keys (a keeper's device), kept in the crypto store.
const { DeviceId, OlmMachine, UserId } = require("@matrix-org/matrix-sdk-crypto-wasm");
require("fake-indexeddb/auto");

describe("fork: refused secret devices", () => {
    test("set, read back, and kept across a reopened store", async () => {
        const user = new UserId("@alice:example.org");
        const name = `refused-${Date.now()}`;
        let machine = await OlmMachine.initialize(user, new DeviceId("ALICEWEB"), name, "pw");
        expect(await machine.refusedSecretDevices()).toEqual([]);
        await machine.setRefusedSecretDevices(["KKEEPER0001", "KKEEPER0002"]);
        expect((await machine.refusedSecretDevices()).sort()).toEqual(["KKEEPER0001", "KKEEPER0002"]);
        machine.close();
        machine = await OlmMachine.initialize(user, new DeviceId("ALICEWEB"), name, "pw");
        expect((await machine.refusedSecretDevices()).sort()).toEqual(["KKEEPER0001", "KKEEPER0002"]);
        await machine.setRefusedSecretDevices([]);
        expect(await machine.refusedSecretDevices()).toEqual([]);
        machine.close();
    });
});
