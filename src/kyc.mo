
import ICRC17Types "./icrc17_types";
import CandyTypes "./candyTypes";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import TrieMap "mo:base/TrieMap";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Hash "mo:base/Hash";
import Canistergeek "mo:canistergeek/canistergeek";

shared (install) actor class Kyc(owner: Principal,record : Principal,newRecord : Principal) = this {
    type TokenSpec = ICRC17Types.TokenSpec;
    public type AccountIdentifier = Text;
    type User = {
        // No notification
        #address : AccountIdentifier;
        // defaults to sub account 0
        #principal : Principal;
    };
    type KYCResult = ICRC17Types.KYCResult;
    type AmlResult = ICRC17Types.AmlResult;
    type VerificationResult = ICRC17Types.VerificationResult;
    type KYCLevel = ICRC17Types.KYCLevel;
    type Access = ICRC17Types.Access;
    type Channel = ICRC17Types.Channel;
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

    //kyc verification whitelist
    stable var _whitelist : [Principal] = [];
    public shared(msg) func addwhitelist(whitelist : [Principal]) : async () {
        assert(msg.caller == Principal.fromText("6cwki-y67rz-mdivc-qqrf3-hqnz4-4vzml-ucxo5-mbuwp-ouak4-siv52-mqe"));
        _whitelist := Array.append(_whitelist,whitelist);
    };

    public shared(msg) func delWhitelist(whitelists : [Principal]) : async () {
        assert(msg.caller == Principal.fromText("6cwki-y67rz-mdivc-qqrf3-hqnz4-4vzml-ucxo5-mbuwp-ouak4-siv52-mqe"));
        for(whitelist in whitelists.vals()) {
            _whitelist := Array.filter<Principal>(_whitelist,func(v){v != whitelist});
        };
    };

    public query(msg) func getWhitelist() : async [Principal] {
        _whitelist
    };

    //origyn canister channel
    //judge canister from co_owned/gold
    stable var _routers_entries : [(Principal,Channel)]= [];
    var _routers : TrieMap.TrieMap<Principal,Channel> = TrieMap.fromEntries(_routers_entries.vals(),Principal.equal,Principal.hash);
    public shared(msg) func setRouter(canister : Principal,channel : Channel) : async () {
        assert(msg.caller == Principal.fromText("6cwki-y67rz-mdivc-qqrf3-hqnz4-4vzml-ucxo5-mbuwp-ouak4-siv52-mqe"));
        _routers.put(canister,channel)
    };

    public query func getAllRouters() : async [(Principal,Channel)]{
        Iter.toArray(_routers.entries())
    };

    //exchange rate
    //symbol:ICPCHF OGYCHF
    stable var _ex_rate_entries : [(Text,Rate)]= [];
    var _ex_rate : TrieMap.TrieMap<Text,Rate> = TrieMap.fromEntries(_ex_rate_entries.vals(),Text.equal,Text.hash);
    type ExRate = {
        pair : Text;
        rate : Rate;
    };
    public shared(msg) func setExRate(exs:[ExRate]) : async () {
        assert(msg.caller == Principal.fromText("6cwki-y67rz-mdivc-qqrf3-hqnz4-4vzml-ucxo5-mbuwp-ouak4-siv52-mqe"));
        for(exRate in exs.vals()){
            _ex_rate.put(exRate.pair,exRate.rate);
        };
    };

    public query(msg) func getAllExRates() : async [(Text,Rate)] {
        Iter.toArray(_ex_rate.entries());
    };

    public query func getExRate(symbol : Text) : async Rate {
        _get_ex_rate(symbol)
    };

    public query func getExRateByToken(token : TokenSpec) : async (Rate,Nat) {
        _get_ex_rate_by_token(token)
    };

    func _get_ex_rate(symbol : Text) : Rate{
        let pair_symbol = symbol#"CHF";
        Debug.print("pair:"#pair_symbol);
        switch(_ex_rate.get(pair_symbol)){
            case (?rate){
                rate
            };
            case _ {
                Debug.trap("nyi");
            };
        };
    };

    func _get_ex_rate_by_token(token : TokenSpec) : (Rate,Nat) {
        switch(token){
            case (#IC(icToken)){
                let symbol = icToken.symbol;
                Debug.print("symbol:"#symbol);
                return (_get_ex_rate(symbol),icToken.decimals);
            };
            case _ {
                Debug.trap("nyi");
            }
        }
    };

    //kyc status
    stable var _kyc_status_entries : [(KYCAccount,KYCLevel)] = [];
    var _kyc_status : TrieMap.TrieMap<KYCAccount,KYCLevel> = TrieMap.fromEntries(_kyc_status_entries.vals(),ICRC17Types.account_equal,ICRC17Types.account_hash);
    public query func getKycStatus(account : KYCAccount) : async ?KYCLevel {
        _kyc_status.get(account)
    };

    type UpdateKycStatusReq = {
        account : KYCAccount;
        kycLevel : KYCLevel
    };
    public shared(msg) func batch_update_kyc_status(statuss : [UpdateKycStatusReq]) : async () {
        assert(msg.caller == Principal.fromText("6cwki-y67rz-mdivc-qqrf3-hqnz4-4vzml-ucxo5-mbuwp-ouak4-siv52-mqe"));
        for(status in statuss.vals()){
            _kyc_status.put(status.account,status.kycLevel);
            _customers := Array.filter<KYCAccount>(_customers,func(v){v != status.account});
        };
    };

    public query func getAllKycStatus() : async [(KYCAccount,KYCLevel)] {
        Iter.toArray(_kyc_status.entries())
    };

    func _kyc_check(counterparty: KYCAccount,channel : Channel) : VerificationResult {
        let userKycLevel = 
        switch(_kyc_status.get(counterparty)){
            case (?kycLevel){
                kycLevel
            };
            case _ {
                #NA;
            };
        };
        switch(_kyc_channel_access.get(channel)){
            case (?channel_access){
                switch(channel_access.get(userKycLevel)){
                    case (?#Pass){
                        return #Pass
                    };
                    case (?#Fail){
                        return #Fail
                    };
                    case _ {
                        return #Pass
                    };
                };
            };
            case _ {
                return #NA
            }
        }
    };

    //aml
    stable var _user_trade_amount_entries : [(KYCAccount,[(Channel,Nat)])] = [];
    var _user_trade_amount = TrieMap.TrieMap<KYCAccount,TrieMap.TrieMap<Channel,Nat>>(ICRC17Types.account_equal,ICRC17Types.account_hash);
    stable var _kyc_channel_access_entries : [(Channel,[(KYCLevel,Access)])] = [];
    var _kyc_channel_access = TrieMap.TrieMap<Channel,TrieMap.TrieMap<KYCLevel,Access>>(ICRC17Types.channel_equal,ICRC17Types.channel_hash);//channel : keyLevel : Limit

    public query func getAllTradeAmount() : async [(KYCAccount,[(Channel,Nat)])]{
        let  kyc_channel_access: TrieMap.TrieMap<KYCAccount, [(Channel, Nat)]> = TrieMap.TrieMap<KYCAccount, [(Channel,Nat)]>(ICRC17Types.account_equal,ICRC17Types.account_hash);
        for ((channel: KYCAccount, value: TrieMap.TrieMap<Channel, Nat>) in _user_trade_amount.entries()) {
            let inner : [(Channel, Nat)] = Iter.toArray<(Channel, Nat)>(value.entries());
            kyc_channel_access.put(channel, inner);
        };
        Iter.toArray(kyc_channel_access.entries());
    };

    public shared(msg) func setKycAccess(channel : Channel,kycLevel : KYCLevel,access : Access) : async () {
        assert(msg.caller == Principal.fromText("6cwki-y67rz-mdivc-qqrf3-hqnz4-4vzml-ucxo5-mbuwp-ouak4-siv52-mqe"));
        switch(_kyc_channel_access.get(channel)){
            case (?kyc_channel_access){
                kyc_channel_access.put(kycLevel,access);
                _kyc_channel_access.put(channel,kyc_channel_access);
            };
            case _ {
                var newkyc_channel_access = TrieMap.TrieMap<KYCLevel,Access>(ICRC17Types.kycLevel_equal,ICRC17Types.kycLevel_hash);
                newkyc_channel_access.put(kycLevel,access);
                _kyc_channel_access.put(channel,newkyc_channel_access);
            }
        };
    };

    public query func getAllKycAccess() : async [(Channel,[(KYCLevel,Access)])] {
        let  kyc_channel_access: TrieMap.TrieMap<Channel, [(KYCLevel, Access)]> = TrieMap.TrieMap<Channel, [(KYCLevel,Access)]>(ICRC17Types.channel_equal, ICRC17Types.channel_hash);
        for ((channel: Channel, value: TrieMap.TrieMap<KYCLevel, Access>) in _kyc_channel_access.entries()) {
            let inner : [(KYCLevel, Access)] = Iter.toArray<(KYCLevel, Access)>(value.entries());
            kyc_channel_access.put(channel, inner);
        };
        Iter.toArray(kyc_channel_access.entries());
    };


    func _aml_check(request : KYCCanisterRequest,channel : Channel) : AmlResult {
        var verificationResult : VerificationResult = #NA;
        var amount = 0;
        let userKycLevel = 
        switch(_kyc_status.get(request.counterparty)){
            case (?kycLevel){
                kycLevel
            };
            case _ {
                #NA;
            };
        };
        switch(_kyc_channel_access.get(channel)){
            case (?channel_access){
                switch(channel_access.get(userKycLevel)){
                    case (?access){
                        switch(access){
                            case (#Pass){
                                verificationResult := #Pass;
                            };
                            case (#Limit(amount_chf)){
                                let tradeAmount = 
                                switch(_user_trade_amount.get(request.counterparty)){
                                    case (?channel_amount){
                                        switch(channel_amount.get(channel)){
                                            case (?amount){amount};
                                            case _ {0}
                                        };
                                    };
                                    case _ {0};
                                };
                                if(amount_chf > tradeAmount){
                                    switch(request.token){
                                        case (?token){
                                            var avaliableAmount = amount_chf - tradeAmount;
                                            let (rate,decimals) = _get_ex_rate_by_token(token);
                                            avaliableAmount := Nat.div(avaliableAmount * rate.percison,rate.rate)* Nat.pow(10,decimals);//chf转token，需要乘上10^8
                                            verificationResult := #Pass;
                                            amount := avaliableAmount;
                                        };
                                        case _ {//Aml is requered but no token passed
                                            verificationResult := #Fail; 
                                        };
                                    }
                                }else{
                                    verificationResult := #Fail;
                                };
                            };
                            case (#Fail){
                                verificationResult := #Fail;
                            };
                        }
                    };
                    case _ {};
                };
            };
            case _ {};
        };
        return {
            verificationResult = verificationResult;
            token = request.token;
            amount = ?amount;
        };
    };

    //for origyn
    //KYC/AML verification
    public shared(msg) func icrc17_kyc_request(request: KYCCanisterRequest) : async KYCResult {
        canistergeekLogger.logMessage(
            "\nfunc_name: icrc17_kyc_request"#
            "\ncaller:"#debug_show(msg.caller)#
            "\nrequest:"#debug_show(request)#"\n\n"
        );
        let channel = 
        switch(_routers.get(msg.caller)){
            case (?channel){channel};
            case _ {#Co_owned};//default Co_owned
        };
        let amlResult = _aml_check(request,channel);
        let kycResult = _kyc_check(request.counterparty,channel);
        canistergeekLogger.logMessage(
            "\nfunc_name: icrc17_kyc_request"#
            "\ncaller:"#debug_show(msg.caller)#
            "\nkcyResult:"#debug_show(kycResult)#
            "\namlResult:"#debug_show(amlResult)#"\n\n"
        );
        return {
            kyc = kycResult;
            aml = amlResult.verificationResult;
            token = amlResult.token;
            amount = amlResult.amount;
            message = null;//TODO
            timeout = null;//TODO
            extensible = null;
        }
    };

    //Notifications - The NFT canister will deduct the executed amount from the KYC cache upon a successful transaction. It will then notify the
    //KYC canister that the transaction executed. It is up to the KYC canister to manage state so that if the NFT canister asks for a clearance
    //request again, the KYC canister should take into account any past transaction during a regulatory period.
    public shared(msg) func icrc17_kyc_notification(notification: KYCNotification) : () {
        canistergeekLogger.logMessage(
            "\nfunc_name: icrc17_kyc_notification"#
            "\ncaller:"#debug_show(msg.caller)#
            "\nrequest:"#debug_show(notification)#"\n\n"
        );
        switch(_routers.get(msg.caller)){
            case (?channel){
                _add_user_trade_amount(channel,notification);
            };
            case _ {
                assert(false);
            };
        };
        
    };

    public shared(msg) func icrc17_kyc_notification2(notification: KYCNotification) : async () {
        canistergeekLogger.logMessage(
            "\nfunc_name: icrc17_kyc_notification2"#
            "\ncaller:"#debug_show(msg.caller)#
            "\nrequest:"#debug_show(notification)#"\n\n"
        );
        switch(_routers.get(msg.caller)){
            case (?channel){
                _add_user_trade_amount(channel,notification);
            };
            case _ {
                assert(false);
            };
        };
        
    };

    func _add_user_trade_amount(channel : Channel,notification: KYCNotification) {
        switch(notification.token,notification.amount){
            case (?token,?amount){
                let (rate,decimals) = _get_ex_rate_by_token(token);
                let amount_chf = Nat.div(Nat.div(amount * rate.rate,rate.percison),Nat.pow(10,decimals));//token转chf，需要除去decimal
                switch(_user_trade_amount.get(notification.counterparty)){
                    case (?channel_trade_amount){
                        switch(channel_trade_amount.get(channel)){
                            case (?amount){
                                channel_trade_amount.put(channel,amount + amount_chf);
                                _user_trade_amount.put(notification.counterparty,channel_trade_amount);
                            };
                            case _ {
                                channel_trade_amount.put(channel,amount_chf);
                                _user_trade_amount.put(notification.counterparty,channel_trade_amount);
                            };
                        }
                    };
                    case _ {
                        var newChannel_trade_amout = TrieMap.TrieMap<Channel,Nat>(ICRC17Types.channel_equal,ICRC17Types.channel_hash);
                        newChannel_trade_amout.put(channel,amount_chf);
                        _user_trade_amount.put(notification.counterparty,newChannel_trade_amout);
                    };
                };
            };
            case _ {//without token&amount
                assert(false);
            };
        }
    };

    //user 
    public query(msg) func user_kyc_request(account : KYCAccount) : async KYCLevel {
        switch(_kyc_status.get(account)){
            case (?kycLevel){
                kycLevel
            };
            case _ {
                #NA
            };
        }
    };

    stable var _customers : [KYCAccount] = [];
    public shared(msg) func addSubmitKyc(customer : KYCAccount) : async (){
        assert(msg.caller == Principal.fromText("6cwki-y67rz-mdivc-qqrf3-hqnz4-4vzml-ucxo5-mbuwp-ouak4-siv52-mqe"));
        _customers := Array.append(_customers,[customer]);
    };
    
    public query func getCustomerKyc() : async [KYCAccount] {
        _customers
    };


    // canistergeekLogger
    stable var _canistergeekLoggerUD: ? Canistergeek.LoggerUpgradeData = null;
    private let canistergeekLogger = Canistergeek.Logger();

    public query ({caller}) func getCanisterLog(request: ?Canistergeek.CanisterLogRequest) : async ?Canistergeek.CanisterLogResponse {
        assert(caller == Principal.fromText("bkwxo-dw742-3sf74-52tlq-3nosz-njz3i-myjlf-5w7x2-iic4j-rv765-gqe"));
        return canistergeekLogger.getLog(request);
    };

    system func preupgrade() {
        _ex_rate_entries := Iter.toArray(_ex_rate.entries());
        _kyc_status_entries := Iter.toArray(_kyc_status.entries());

        let  kyc_channel_access_entries: TrieMap.TrieMap<Channel, [(KYCLevel, Access)]> = TrieMap.TrieMap<Channel, [(KYCLevel,Access)]>(ICRC17Types.channel_equal, ICRC17Types.channel_hash);
        for ((channel: Channel, value: TrieMap.TrieMap<KYCLevel, Access>) in _kyc_channel_access.entries()) {
            let inner : [(KYCLevel, Access)] = Iter.toArray<(KYCLevel, Access)>(value.entries());
            kyc_channel_access_entries.put(channel, inner);
        };
        _kyc_channel_access_entries := Iter.toArray(kyc_channel_access_entries.entries());

        let  user_trade_amount_entries: TrieMap.TrieMap<KYCAccount, [(Channel,Nat)]> = TrieMap.TrieMap<KYCAccount, [(Channel,Nat)]>(ICRC17Types.account_equal,ICRC17Types. account_hash);
        for ((account: KYCAccount, value: TrieMap.TrieMap<Channel,Nat>) in _user_trade_amount.entries()) {
            let inner : [(Channel,Nat)] = Iter.toArray<(Channel,Nat)>(value.entries());
            user_trade_amount_entries.put(account, inner);
        };
        _user_trade_amount_entries := Iter.toArray(user_trade_amount_entries.entries());
        _canistergeekLoggerUD := ? canistergeekLogger.preupgrade();
        _routers_entries := Iter.toArray(_routers.entries());
    };

    system func postupgrade(){
        for ((key: Channel, value: [(KYCLevel, Access)]) in _kyc_channel_access_entries.vals()) {
            let inner: TrieMap.TrieMap<KYCLevel, Access> = TrieMap.fromEntries<KYCLevel, Access>(value.vals(),ICRC17Types.kycLevel_equal, ICRC17Types.kycLevel_hash);
            _kyc_channel_access.put(key, inner);
        };
        for ((key: KYCAccount, value: [(Channel, Nat)]) in _user_trade_amount_entries.vals()) {
            let inner: TrieMap.TrieMap<Channel, Nat> = TrieMap.fromEntries<Channel, Nat>(value.vals(),ICRC17Types.channel_equal, ICRC17Types.channel_hash);
            _user_trade_amount.put(key, inner);
        };
        _kyc_channel_access_entries := [];
        _user_trade_amount_entries := [];
        canistergeekLogger.postupgrade(_canistergeekLoggerUD);
        _canistergeekLoggerUD := null;
        _routers_entries := [];
        canistergeekLogger.setMaxMessagesCount(5000);
        canistergeekLogger.logMessage("postupgrade");
    };
}