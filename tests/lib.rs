use radix_engine::transaction::TransactionExecutor;
use scrypto::crypto::{EcdsaPrivateKey, EcdsaPublicKey};
use radix_engine::ledger::*;
use radix_engine::transaction::*;
use scrypto::prelude::*;

struct Account {
    public_key: EcdsaPublicKey,
    private_key: EcdsaPrivateKey,
    account: ComponentAddress,
}

impl From<(EcdsaPublicKey, EcdsaPrivateKey, ComponentAddress)> for Account {
    fn from(e: (EcdsaPublicKey, EcdsaPrivateKey, ComponentAddress)) -> Self {
        Account { public_key: e.0, private_key: e.1, account: e.2 }
    }
}

struct TestEnv<'a, L: SubstateStore> {
    executor: TransactionExecutor<'a, L>,
    bank: ComponentAddress,
    owner: Account,
    customer: Account,
}

fn set_up_test_env<'a, L: SubstateStore>(ledger: &'a mut L) -> TestEnv<'a, L> {
    let mut executor = TransactionExecutor::new(ledger, false);
    let owner: Account = executor.new_account().into();
    let customer: Account = executor.new_account().into();
    let package = executor.publish_package(compile_package!()).unwrap();
    
    let receipt = executor
        .validate_and_execute(
            &TransactionBuilder::new()
                .call_function(
                    package,
                    "Bank",
                    "new",
                    //TODO: need to build transaction to include bucket with inital funding
                    args![]
                )
                .call_method_with_all_resources(owner.account, "deposit_batch")
                .build(executor.get_nonce([owner.public_key]))
                .sign([&owner.private_key]),
        )
        .unwrap();
    let bank = receipt.new_component_addresses[0];

    TestEnv {
        executor,
        bank,
        owner,
        customer,
    }
}

fn register_customer<'a, L: SubstateStore>(env: &mut TestEnv<'a, L>) -> (Bucket, ResourceAddress) {
    let mut receipt = env
        .executor
        .validate_and_execute(
            &TransactionBuilder::new()
                .call_method(env.bank, "customer_registration", args!["Satoshi", "Nakamoto"])
                .call_method_with_all_resources(env.customer.account, "deposit_batch")
                .build(env.executor.get_nonce([env.customer.public_key]))
                .sign([&env.customer.private_key]),
        )
        .unwrap();
    assert!(receipt.result.is_ok());
    let encoded = receipt.outputs.swap_remove(0).raw;
    scrypto_decode(&encoded).unwrap()
}


#[test]
fn should_register_customer() {
    //NOTE Will fail - see TODO in set_up_test_env above
    let mut ledger = InMemorySubstateStore::with_bootstrap();
    let mut env = set_up_test_env(&mut ledger);
    println!("{:?}", env.bank);

    let (_, _) = register_customer(&mut env);
}
