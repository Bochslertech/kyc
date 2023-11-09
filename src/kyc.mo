
import ICRC17Types "./icrc17_types";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import TrieMap "mo:base/TrieMap";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Hash "mo:base/Hash";

shared (install) actor class Kyc(owner: Principal) = this {
    type TokenSpec = ICRC17Types.TokenSpec;
    type KYCResult = ICRC17Types.KYCResult;
    type AmlResult = ICRC17Types.AmlResult;
    type VerificationResult = ICRC17Types.VerificationResult;
    type KYCLevel = ICRC17Types.KYCLevel;
    type Access = ICRC17Types.Access;
    type Rate = ICRC17Types.Rate;
    type KYCAccount = ICRC17Types.KYCAccount;
    type KYCCanisterRequest = ICRC17Types.KYCCanisterRequest;
    type KYCNotification = ICRC17Types.KYCNotification;

    private stable var _owner : Principal= owner;
    public shared(msg) func setOwner(owner : Principal) : async () {
        assert(msg.caller == _owner);
        _owner := owner;
    };

    public query(msg) func getOwner() : async Principal {
        _owner
    };

    private stable var _decimal : Nat = 4;
    public shared (msg) func setDecimal(decimal : Nat) : async () {
        assert (msg.caller == _owner);
        _decimal := decimal;
    };

    public query (msg) func getDecimal() : async Nat {
        _decimal;
    };

    //exchange rate
    //symbol:ICPUSD OGYUSD
    stable var _ex_rate_entries : [(Text, Rate)] = [];
    var _ex_rate : TrieMap.TrieMap<Text, Rate> = TrieMap.fromEntries(_ex_rate_entries.vals(), Text.equal, Text.hash);
    type ExRate = {
        pair : Text;
        rate : Rate;
    };
    public shared (msg) func setExRate(exs : [ExRate]) : async () {
        assert (msg.caller == _owner);
        for (exRate in exs.vals()) {
            _ex_rate.put(exRate.pair, exRate.rate);
        };
    };

    func _get_ex_rate(symbol : Text) : Rate {
        let pair_symbol = symbol # "USD";
        Debug.print("pair:" #pair_symbol);
        switch (_ex_rate.get(pair_symbol)) {
            case (?rate) {
                rate;
            };
            case _ {
                Debug.trap("nyi");
            };
        };
    };

    func _get_ex_rate_by_token(token : TokenSpec) : (Rate, Nat) {
        switch (token) {
            case (#IC(icToken)) {
                let symbol = icToken.symbol;
                Debug.print("symbol:" #symbol);
                return (_get_ex_rate(symbol), icToken.decimals);
            };
            case _ {
                Debug.trap("nyi");
            };
        };
    };

    stable var _kyc_status_entries : [(KYCAccount, KYCLevel)] = [];
    var _kyc_status : TrieMap.TrieMap<KYCAccount, KYCLevel> = TrieMap.fromEntries(_kyc_status_entries.vals(), ICRC17Types.account_equal, ICRC17Types.account_hash);
    
    stable var _user_trade_amount_entries : [(Principal, Nat)] = [];
    var _user_trade_amount : TrieMap.TrieMap<Principal, Nat> = TrieMap.fromEntries(_user_trade_amount_entries.vals(), Principal.equal, Principal.hash);
    
    stable var _kyc_access_entries : [(KYCLevel, Access)] = [];
    var _kyc_access = TrieMap.TrieMap<KYCLevel, Access>(ICRC17Types.kycLevel_equal, ICRC17Types.kycLevel_hash); 

    stable var _kyc_tier3_limit_entries : [(KYCAccount, Nat)] = [];
    var _kyc_tier3_limit : TrieMap.TrieMap<KYCAccount, Nat> = TrieMap.fromEntries(_kyc_tier3_limit_entries.vals(), ICRC17Types.account_equal, ICRC17Types.account_hash);

    public shared (msg) func setKycAccess(kycLevel : KYCLevel, access : Access) : async () {
        assert (msg.caller == _owner);
        _kyc_access.put(kycLevel,access);
    };

    public query func getKycStatus(account : KYCAccount) : async ?KYCLevel {
        _kyc_status.get(account);
    };

    public shared (msg) func batch_update_kyc_status(statuss : [{account : KYCAccount;kycLevel : KYCLevel;}]) : async () {
        assert (msg.caller == _owner);
        for (status in statuss.vals()) {
            if (status.kycLevel == #Tier1) {
                let account = switch (status.account) {
                    case (#ICRC1(icrc1)) {
                        icrc1.owner;
                    };
                    case _ {
                        Debug.trap("nyi");
                    };
                };
            };
            _kyc_status.put(status.account, status.kycLevel);
        };
    };

    public query func getAllKycStatus() : async [(KYCAccount, KYCLevel)] {
        Iter.toArray(_kyc_status.entries());
    };

    func _kyc_check(counterparty : KYCAccount) : VerificationResult {
        let userKycLevel = switch (_kyc_status.get(counterparty)) {
            case (?kycLevel) {
                kycLevel;
            };
            case _ {
                #NA;
            };
        };
        switch (_kyc_access.get(userKycLevel)) {
            case (?access) {
               switch(access){
                    case (#Pass){
                        return #Pass;
                    };
                    case (#Fail) {
                        return #Fail;
                    };
                    case (#Limit(_)){
                        return #Pass;
                    };
               };
            };
            case _ {
                return #NA;
            };
        };
    };

    func _aml_check(request : KYCCanisterRequest) : AmlResult {
        var verificationResult : VerificationResult = #Pass;
        var amount = 0;
        let primary = _get_primary_principal(request.counterparty);
        let primary_account = #ICRC1 { owner = primary; subaccount = null };
        let userKycLevel = switch (_kyc_status.get(primary_account)) {
            case (?kycLevel) {
                kycLevel;
            };
            case _ {
                #NA;
            };
        };
        let access : Access = switch (userKycLevel) {
            case (#Tier3) {
                switch (_kyc_tier3_limit.get(primary_account)) {
                    case (?limit_amount) {
                        #Limit(limit_amount);
                    };
                    case _ {
                        #Pass;
                    };
                };
            };
            case _ {
                switch (_kyc_access.get(userKycLevel)) {
                    case (?access) {
                        access
                    };
                    case _ {
                        #Fail;
                    };
                };
            };
        };
        switch (access) {
            case (#Pass) {
                verificationResult := #Pass;
            };
            case (#Limit(amount_usd)) {
                let tradedAmount = switch (_user_trade_amount.get(primary)) {
                    case (?amount) { amount };
                    case _ { 0 };
                };
                if (amount_usd > tradedAmount) {
                    switch (request.token) {
                        case (?token) {
                            var avaliableAmount = amount_usd - tradedAmount;
                            let (rate, decimals) = _get_ex_rate_by_token(token);
                            avaliableAmount := Nat.div(avaliableAmount * rate.percison, rate.rate) * Nat.pow(10, decimals); //usd转token
                            amount := avaliableAmount;
                            switch (request.amount) {
                                case (?tradeAmount) {
                                    if (tradeAmount * Nat.pow(10, _decimal) > avaliableAmount) {
                                        verificationResult := #Fail;
                                    };
                                };
                                case _ {};
                            };
                        };
                        case _ {
                            //Aml is requered but no token passed
                            verificationResult := #Fail;
                        };
                    };
                } else {
                    verificationResult := #Fail;
                };
            };
            case (#Fail) {
                verificationResult := #Fail;
            };
        };
        return {
            verificationResult = verificationResult;
            token = request.token;
            amount = ?amount;
        };
    };
    
    func _add_user_trade_amount(notification : KYCNotification) {
        switch (notification.token, notification.amount) {
            case (?token, ?amount) {
                let (rate, decimals) = _get_ex_rate_by_token(token);
                let amount_usd = Nat.div(Nat.div(amount * Nat.pow(10, _decimal) * rate.rate, rate.percison), Nat.pow(10, decimals)); //token转usd
                let primary_principal = _get_primary_principal(notification.counterparty);
                switch (_user_trade_amount.get(primary_principal)) {
                    case (?amount) {
                        _user_trade_amount.put(primary_principal, amount + amount_usd);
                    };
                    case _ {
                        _user_trade_amount.put(primary_principal, amount_usd);
                    };
                };
            };
            case _ {
                //without token&amount
                assert (false);
            };
        };
    };

    //KYC/AML verification
    public shared (msg) func icrc17_kyc_request(request : KYCCanisterRequest) : async KYCResult {
        let amlResult = _aml_check(request);
        let kycResult = _kyc_check(request.counterparty);
        return {
            kyc = kycResult;
            aml = amlResult.verificationResult;
            token = amlResult.token;
            amount = amlResult.amount;
            message = null; //TODO
            timeout = null; //TODO
            extensible = null;
        };
    };

    //Notifications - The NFT canister will deduct the executed amount from the KYC cache upon a successful transaction. It will then notify the
    //KYC canister that the transaction executed. It is up to the KYC canister to manage state so that if the NFT canister asks for a clearance
    //request again, the KYC canister should take into account any past transaction during a regulatory period.
    public shared (msg) func icrc17_kyc_notification(notification : KYCNotification) : () {
        _add_user_trade_amount(notification);
    };

    func _get_primary_principal(counterparty : KYCAccount) : Principal {
        let pri = switch (counterparty) {
            case (#ICRC1(icrc1)) {
                icrc1.owner;
            };
            case _ {
                Debug.trap("nyi");
            };
        };
    };

    public shared (msg) func setKycTier3Limit(who : Principal, amount : Nat) : async () {
        assert (msg.caller == _owner);
        let primary = _get_primary_principal(#ICRC1 { owner = who; subaccount = null });
        _kyc_tier3_limit.put(#ICRC1 { owner = primary; subaccount = null }, amount * Nat.pow(10, _decimal));
    };

    system func preupgrade() {
        _ex_rate_entries := Iter.toArray(_ex_rate.entries());
        _kyc_status_entries := Iter.toArray(_kyc_status.entries());
        _user_trade_amount_entries := Iter.toArray(_user_trade_amount.entries());
        _kyc_access_entries := Iter.toArray(_kyc_access.entries());
    };

    system func postupgrade() {
        _ex_rate_entries := [];
        _kyc_status_entries := [];
        _user_trade_amount_entries := [];
        _kyc_access_entries := [];
    };
}