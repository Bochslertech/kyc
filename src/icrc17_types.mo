import Hash "mo:base/Hash";
import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
module {
    type PropertyShared = {
        immutable : Bool;
        name : Text;
        value : CandyShared;
    };

    public type CandyShared = {
        #Array : [CandyShared];
        #Blob : Blob;
        #Bool : Bool;
        #Bytes : [Nat8];
        #Class : [PropertyShared];
        #Float : Float;
        #Floats : [Float];
        #Int : Int;
        #Int16 : Int16;
        #Int32 : Int32;
        #Int64 : Int64;
        #Int8 : Int8;
        #Map : [(CandyShared, CandyShared)];
        #Nat : Nat;
        #Nat16 : Nat16;
        #Nat32 : Nat32;
        #Nat64 : Nat64;
        #Nat8 : Nat8;
        #Nats : [Nat];
        #Option : ?CandyShared;
        #Principal : Principal;
        #Set : [CandyShared];
        #Text : Text;
    };

    type ICTokenSpec = {
        canister : Principal;
        decimals : Nat;
        fee : ?Nat;
        id : ?Nat; //used for multi-token canisters
        standard : {
            #DIP20;
            #EXTFungible;
            #ICRC1;
            #Ledger;
            #Other : CandyShared; //for future use
        };
        symbol : Text;
    };

    public type TokenSpec = {
        #Extensible : CandyShared;
        #IC : ICTokenSpec;
    };

    public type VerificationResult = {
        #Pass;
        #Fail;
        #NA;
    };

    public type AmlResult = {
        verificationResult : VerificationResult;
        token : ?TokenSpec;
        amount : ?Nat;
    };

    public type KYCResult = {
        aml : VerificationResult;
        kyc : VerificationResult;
        amount : ?Nat;
        message : ?Text;
        token : ?TokenSpec;
    };

    public type KYCCanisterRequest = {
        amount : ?Nat;
        counterparty : KYCAccount;
        token : ?TokenSpec;
        extensible : ?CandyShared;
    };

    public type KYCNotification = {
        amount : ?Nat;
        counterparty : KYCAccount;
        token : ?TokenSpec;
        metadata : ?CandyShared;
    };

    public type KYCAccount = {
        #Account : [Nat8];
        #Extensible : CandyShared;
        #ICRC1 : {
            owner : Principal;
            subaccount : ?[Nat8];
        };
    };

    public type KYCLevel = {
        #NA;
        #Tier1;
        #Tier2;
        #Tier3;
    };

    public type RiskAssessment = {
        #Low;
        #Medium;
        #High;
    };

    public type UpgradStatus = {
        #AwaitingInput;
        #UnderReview;
        #None;
    };

    public type Access = {
        #Pass; //pass
        #Fail; //fail
        #Limit : Nat; //usd amount limit per month
    };

    public type Rate = {
        rate : Nat;
        percison : Nat;
    };

    public type Benefit = {
        credits : Rate;
        airdrop : Bool;
        earlyLaunchpad : Int;
    };

    public func kycLevel_equal(level1 : KYCLevel, level2 : KYCLevel) : Bool {
        level1 == level2;
    };

    public func kycLevel_hash(level : KYCLevel) : Hash.Hash {
        switch (level) {
            case (#NA) 0;
            case (#Tier1) 1;
            case (#Tier2) 2;
            case (#Tier3) 3;
        };
    };

    public func kycLevel_access(level1 : KYCLevel, level2 : KYCLevel) : Bool {
        switch (level1) {
            case (#NA) {
                switch (level1) {
                    case (#NA) true;
                    case _ false;
                };
            };
            case (#Tier1) {
                switch (level2) {
                    case (#NA) true;
                    case (#Tier1) true;
                    case (#Tier2) false;
                    case (#Tier3) false;
                };
            };
            case (#Tier2) {
                switch (level2) {
                    case (#NA) true;
                    case (#Tier1) true;
                    case (#Tier2) true;
                    case (#Tier3) false;
                };
            };
            case (#Tier3) {
                true;
            };
        };
    };

    public func account_equal(account1 : KYCAccount, account2 : KYCAccount) : Bool {
        let pid1 = switch (account1) {
            case (#ICRC1(icrc1)) {
                icrc1.owner;
            };
            case (#Extensible(#Principal(pid))) {
                pid;
            };
            case _ {
                //暂不支持其他类型
                return false;
            };
        };
        let pid2 = switch (account2) {
            case (#ICRC1(icrc1)) {
                icrc1.owner;
            };
            case (#Extensible(#Principal(pid))) {
                pid;
            };
            case _ {
                //暂不支持其他类型
                return false;
            };
        };
        pid1 == pid2;
    };
    public func account_hash(account : KYCAccount) : Hash.Hash {
        let pid = switch (account) {
            case (#ICRC1(icrc1)) {
                icrc1.owner;
            };
            case (#Extensible(#Principal(pid))) {
                pid;
            };
            case _ {
                Debug.trap("nyi");
            };
        };
        Principal.hash(pid);
    };
};
