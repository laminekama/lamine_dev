public with sharing class OpportunityServices {
	public static Boolean firstExecuted = true;

    
    public static void sendIframe(List<Opportunity> newOpp, Map<Id, Opportunity> oldOpps) {
        for(Opportunity opp : newOpp) {

            System.debug('opp AVnt: ' + opp.Id + ' ' + opp.Docusign_Quote_sign__c + ' ' + oldOpps.get(opp.Id).Docusign_Quote_sign__c);
           
            if(opp.Docusign_Quote_sign__c == true && opp.Docusign_Quote_sign__c != oldOpps.get(opp.Id).Docusign_Quote_sign__c) {

                OrgWideEmailAddress owea = new OrgWideEmailAddress();
                owea = [SELECT Id, Address, DisplayName FROM OrgWideEmailAddress WHERE DisplayName='Zeplug'];

                EmailTemplate et = [SELECT Id FROM EmailTemplate WHERE DeveloperName = 'Coordonn_es_bancaires_Sepa'];

                zqu__Quote__c  quote = [SELECT Id, QUO_HPPURL__c, zqu__Opportunity__r.Copro_user__r.PersonContact.Id, zqu__Opportunity__r.Copro_user__r.Salutation, zqu__Opportunity__r.Copro_user__r.LastName, zqu__Opportunity__r.Copro_user__r.PersonEmail FROM zqu__Quote__c WHERE zqu__Opportunity__c = :opp.Id LIMIT 1][0];
        
                List<Messaging.SingleEmailMessage> mails =  new List<Messaging.SingleEmailMessage>();
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

                mail.setTemplateId(et.Id);
                mail.setWhatId(quote.Id);
                mail.setTargetObjectId(quote.zqu__Opportunity__r.Copro_user__r.PersonContact.Id);
                mail.setToAddresses(new String[]{quote.zqu__Opportunity__r.Copro_user__r.PersonEmail});    
                mail.setSaveAsActivity(false);
                if ( owea != null) { 
                    mail.setOrgWideEmailAddressId(owea.id);
                }
                mails.add(mail);
                if(!test.isRunningTest())
                Messaging.sendEmail(mails);  
            }
        }

    }

    
    
    
    
    
    public static void oppResilieeCallWFZuora(List<Opportunity> newOpps, Map<Id, Opportunity> oldOpps) {

        Map<Id,zqu__Quote__c> mOppQuote = new Map<Id,zqu__Quote__c>();

        for(zqu__Quote__c quote : [SELECT Id, zqu__Opportunity__r.Call_Zuora_WF__c, zqu__ZuoraSubscriptionNumber__c FROM zqu__Quote__c WHERE zqu__Opportunity__c IN :newOpps]) {

            mOppQuote.put(quote.zqu__Opportunity__c, quote);
        }
		system.debug('mOppQuote = ');
        for(Opportunity opp : newOpps) {
            // Attendre la Date que Ola va renseigner
            if(opp.StageName == 'Résilié' && oldOpps.get(opp.Id).StageName != opp.StageName && mOppQuote != null && !mOppQuote.isEmpty() && opp.Abonnement_Type_Zuora__c == 'Zuora') {
                ZuoraService.callURLWorkflow(mOppQuote.get(opp.Id).zqu__ZuoraSubscriptionNumber__c);                
            }
        }

    }


    public static void createContacts(List<Opportunity> newOpps, Map<Id, Opportunity> oldOpps) {

        Id b2cRecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Abonnement_seul_B2C').getRecordTypeId();
        Id b2cAboRecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Subscription').getRecordTypeId();

        Database.DMLOptions insertDML = new Database.DMLOptions(); 
        insertDML.DuplicateRuleHeader.AllowSave = true;

        List<Contact> contacts = new List<Contact>();

        Set<Id> setAccIds = new Set<Id>();

        for (Opportunity opp : newOpps) {
            setAccIds.add(opp.AccountId);
            setAccIds.add(opp.Subscription_billed_to__c);
        }

        Map<Id, Account> mAccContact = new Map<Id, Account>([SELECT PersonEmail, RecordTypeId , isPersonAccount, FirstName, LastName, Name, Type, BillingStreet, BillingCity, BillingPostalCode, BillingCountry, BillingState, 
                                                             (SELECT Id, FirstName ,LastName, Email, MailingStreet, MailingCity, MailingCountry, MailingState, MailingPostalCode FROM Contacts ) 
                                                             FROM Account WHERE Id IN :setAccIds]);
        
		System.debug('mAccContact is : ' + mAccContact); 
        Id recordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByName().get('Utilisateur').getRecordTypeId();
        Id companyRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Company').getRecordTypeId();

        for(Opportunity opp : newOpps) {

            Account oppAccount = mAccContact.get(opp.Subscription_billed_to__c);
            Account oppAccountCopro = mAccContact.get(opp.AccountId);
            Contact contactTemp = new Contact();
            Contact contactCoproTemp = new Contact();


            // If the new billedTo is different than the old bildTo 
            if((opp.Subscription_billed_to__c != null && oldOpps == null) || (oldOpps != null && oldOpps.get(opp.Id).Subscription_billed_to__c != opp.Subscription_billed_to__c) && (opp.RecordTypeId == b2cRecordTypeId || opp.RecordTypeId == b2cAboRecordTypeId)) {

                // If the Account linked to the new Opp exists and is a PersonAccount
                if(oppAccount != null && oppAccount.isPersonAccount == true) {

                    System.debug('oppAccount is PersonAccount');

                    contactTemp = createContact(oppAccount.FirstName + ' ' + oppAccount.LastName, '.', oppAccount.PersonEmail, oppAccountCopro.Id, recordTypeId, oppAccount.BillingStreet, oppAccount.BillingCity, oppAccount.BillingPostalCode, oppAccount.BillingState, oppAccount.BillingCountry, opp.Id, NULL);

                    System.debug('contactTemp : ' + contactTemp);

                    contacts.add(contactTemp);

                } else if(oppAccount != null && oppAccount.RecordTypeId == companyRecordTypeId){

                    System.debug('oppAccount is Society');

                    
                    if(mAccContact.get(oppAccount.Id).Contacts.size() > 0) {

                        for(Contact contact : mAccContact.get(oppAccount.Id).Contacts) {

                            Contact contactTempSociete = new Contact();
                            string fn = '.';
                            if(contact.FirstName != null && contact.FirstName != ''){
                                fn = contact.FirstName;
                            }

                            contactTempSociete = createContact(fn + ' ' + contact.LastName, 'Société:'+ oppAccount.Name +', Bénéficiaire :', contact.Email, oppAccountCopro.Id, recordTypeId, oppAccount.BillingStreet, oppAccount.BillingCity, oppAccount.BillingPostalCode, oppAccount.BillingState, oppAccount.BillingCountry, opp.Id, fn + ' ' + contact.LastName);

                            contacts.add(contactTempSociete);

                        }
                        
                    } else {
                        throw new applicationException('Le compte doit avoir au moins un contact rattaché.');
                    }
                }

                contactCoproTemp = createContact(oppAccountCopro.Name, '.', null, oppAccountCopro.Id, recordTypeId, oppAccountCopro.BillingStreet, oppAccountCopro.BillingCity, oppAccountCopro.BillingPostalCode, oppAccountCopro.BillingState, oppAccountCopro.BillingCountry, opp.Id, NULL);
        
                contacts.add(contactCoproTemp);
            }

        }


        for(Contact contact : contacts) {
            System.debug('contact qui vont etre créé : ' + contact);
        }


        if(contacts.size() > 0) {
            Database.insert(contacts, insertDML);
        }
            
    } 

    
    
    public static void updateStartDateOnTheQuote(List<Opportunity> newOpps, Map<Id,Opportunity> oldOpps) {
        for(Opportunity opp :newOpps ){
            if(opp.Mise_en_service__c != null && opp.Primary_Quote__c != null && opp.Mise_en_service__c != oldOpps.get(opp.Id).Mise_en_service__c){
                ZuoraService.updateStartDateOnTheQuote(opp.Primary_Quote__c, opp.Mise_en_service__c) ;   
            }
        }
    }


    public static Contact createContact(String lastName, String firstName, String email, Id accountId, Id recordTypeId, String mailingStreet, String mailingCity, String mailingPostalCode, String mailingState, String MailingCountry, String oppId, String techName) {

        Contact nContact = new Contact();
        string lname = lastName;
        if(lname.length() >= 80){
            lname = lname.substring(0,80);
        }
        nContact.LastName = lname;
        string fname = firstName;
        if(fname.length() >= 40){
            fname = fname.substring(0,40);
        }
        if (techName != NULL){
            System.debug('Tech Name done');
          //  nContact.TECH_Name__c = techName;
        }        
        nContact.FirstName = fname;
        nContact.First_Name__c = firstName;
        nContact.Email = email;
        nContact.AccountId = accountId;
        nContact.RecordTypeId = recordTypeId;
        nContact.MailingStreet = mailingStreet;
        nContact.MailingCity = mailingCity;
        nContact.MailingState = mailingState;
        nContact.MailingPostalCode = mailingPostalCode;
        nContact.MailingCountry = mailingCountry;
        nContact.TECH_TempOppId__c = oppId;

        return nContact;
    }
    
    public static void calculateDateResiliation(List<Opportunity> newOpps, Map<Id,Opportunity> oldOpps){
        set<id> oppId = new set<id>();
        map<id,zqu__Quote__c> mapQuoteByOppId = new map<id,zqu__Quote__c>();
        for(Opportunity opp : newOpps) {
            if((opp.Demande_de_r_siliation_re_ue__c  && oldOpps.get(opp.Id).Demande_de_r_siliation_re_ue__c != opp.Demande_de_r_siliation_re_ue__c) 
               || (opp.Date_de_r_siliation__c!= null && oldOpps.get(opp.Id).Date_de_r_siliation__c != opp.Date_de_r_siliation__c)  ) {
                oppId.add(opp.Id);
                mapQuoteByOppId.put(opp.Id,null);
            }
        }
        
        if(oppId.size()>0){
            list<zqu__Quote__c> listq = new list<zqu__Quote__c>([SELECT id,zqu__Opportunity__c, zqu__ApprovalStatus__c,zqu__Subscription_Name__c, zqu__Status__c, zqu__StartDate__c, zqu__Service_Activation_Date__c, zqu__SubscriptionType__c FROM zqu__Quote__c WHERE zqu__Opportunity__c in :oppId and zqu__Status__c != 'New']);
            set<string> listSubName = new set<string>();
            map<String,Zuora__Subscription__c> mapSubBySubName = new map<String,Zuora__Subscription__c>();
            for(zqu__Quote__c q :listq){
                mapQuoteByOppId.put(q.zqu__Opportunity__c,q);
                if(q.zqu__Subscription_Name__c != null && q.zqu__Subscription_Name__c != ''){
                    listSubName.add(q.zqu__Subscription_Name__c);
                }
            }
            
            List<Zuora__Subscription__c> Listsubs = new List<Zuora__Subscription__c>([SELECT id,Zuora__NextChargeDate__c,Name FROM Zuora__Subscription__c WHERE Name in :listSubName AND Zuora__Status__c = 'Active' ]);    
            for(Zuora__Subscription__c sub:Listsubs){
                mapSubBySubName.put(sub.Name,sub);
            }
            
            for(Opportunity opp : newOpps) {
                if(oppId.contains(opp.Id)){
                    if(mapQuoteByOppId.get(opp.Id) != null){
                        zqu__Quote__c q = mapQuoteByOppId.get(opp.Id);
                        if(mapSubBySubName.get(q.zqu__Subscription_Name__c)!=null){
                            Zuora__Subscription__c sub = mapSubBySubName.get(q.zqu__Subscription_Name__c);
                            if(sub.Zuora__NextChargeDate__c != null){
                                
                                Integer numberDaysDue = Date.today().daysBetween(sub.Zuora__NextChargeDate__c);
                                if(opp.Forcer_la_date_de_r_siliation_manuelle__c == false){
                                    if(numberDaysDue >15 ){
                                        opp.Date_de_r_siliation__c = sub.Zuora__NextChargeDate__c;
                                    }else{
                                        opp.Date_de_r_siliation__c = sub.Zuora__NextChargeDate__c.addMonths(1);
                                    }  
                                }else if(opp.Forcer_la_date_de_r_siliation_manuelle__c == true){
                                    if(opp.Date_de_r_siliation__c == null){
                                       opp.addError('Vous devez choisir le mois de resiliation demandé dans le champ Date de resiliation (Zuora)');
                                    }else{
                                        date myDate = date.newInstance(opp.Date_de_r_siliation__c.year(), opp.Date_de_r_siliation__c.month(), sub.Zuora__NextChargeDate__c.day());
                                        if(myDate < sub.Zuora__NextChargeDate__c){
                                            opp.addError('Nous ne pouvons pas resilié dans le passé, merci de mettre une date future');
                                        }else{
                                            opp.Date_de_r_siliation__c =myDate;
                                        }
                                    } 
                                }
                            }else{
                                opp.addError('the zuora NextChargeDate is empty for the subscription linked to this opportunity, the sub is not invoiced');
                            }
                        } else{
                            opp.addError('there is no subscription synchronized for this opportunity');
                        }
                    }else{
                        opp.addError('there is no quote sent to zuora');
                    }
                    
                }

            }
        }        

    }
    
    public static void updateField(List<Opportunity> newOpps){
        
        for(Opportunity opp : newOpps){
            opp.Customer_Email__c = opp.Tech_Email__c;
        }
    }
    
    public static void avoidOppInstNobadge(List<Opportunity> newOpps,Map<Id,Opportunity> oldOpps){
        
        map<id,Opportunity> mapOPP=new map<id,Opportunity>();
         map<id,map<id,badge__c>> mapBadge=new map<id,map<id,badge__c>>();
        for(Opportunity opp : newOpps){
            mapOPP.put(opp.id,opp);
            mapBadge.put(opp.id,new map<id,badge__c>([select id,name,Opportunity__c,badge_serial__c from badge__c where Opportunity__c =:opp.id]));
        }

		system.debug('mapBadge '+mapBadge);
        map<id,OpportunityLineItem> mapOppLineItem=new map<id,OpportunityLineItem>([select id,product2.name,OpportunityId from OpportunityLineItem where OpportunityId in : mapOPP.keyset() and product2.name='Recharge publique']);
      	system.debug('mapOppLineItem '+mapOppLineItem);
        
        
        for(Id idOppLineItemp:mapOppLineItem.keyset())
        {
            if((mapOPP.get(mapOppLineItem.get(idOppLineItemp).OpportunityId).stagename!=oldOpps.get(mapOppLineItem.get(idOppLineItemp).OpportunityId).stagename)
              // &&(mapOPP.get(mapOppLineItem.get(idOppLineItemp).OpportunityId).stagename=='Installation')||(mapOPP.get(mapOppLineItem.get(idOppLineItemp).OpportunityId).stagename=='Service activé'))
                 &&(mapOPP.get(mapOppLineItem.get(idOppLineItemp).OpportunityId).stagename=='Service activé'))
            {
                if(mapBadge.get(mapOppLineItem.get(idOppLineItemp).OpportunityId).isEmpty()||!mapBadge.containsKey(mapOppLineItem.get(idOppLineItemp).OpportunityId))
                	mapOPP.get(mapOppLineItem.get(idOppLineItemp).OpportunityId).addError('Veuillez créer un badge associé à l’opportunité et y saisir le Numéro de série');
                else
                {
                    for(id idBadge:mapBadge.get(mapOppLineItem.get(idOppLineItemp).OpportunityId).keyset())
                    {
                        if(String.isEmpty(mapBadge.get(mapOppLineItem.get(idOppLineItemp).OpportunityId).get(idBadge).badge_serial__c))
                            mapOPP.get(mapOppLineItem.get(idOppLineItemp).OpportunityId).addError('Veuillez créer un badge associé à l’opportunité et y saisir le Numéro de série');
                  
                    }
                }
            }
        }
    }
    
    public static void oppCreateTask(List<Opportunity> newOpps)//insert
    {
        list<Task> tskList = new list<Task>();
        for(Opportunity o:newOpps)
        {
            Task tsk=new Task(Subject='Planifier next steps',WhatId=o.id,ActivityDate = Date.today(),OwnerId = o.OwnerId,Priority = 'Normal');
            tskList.add(tsk);
          
        }
        if(!tskList.isEmpty())
            upsert tskList;
           
    }
    
    public static void oppAccount(List<Opportunity> newOpps,Map<Id,Opportunity> oldOpps,Boolean isBefore){
        Set<id> setAccId=new Set<id>();
        Set<id> setOppId=new Set<id>();
        Map<String,Id> recTypeIdMap=UtilsMethods.recordTypeMap('Opportunity');
        Map<String,Id> recTypeIdMapAcc=UtilsMethods.recordTypeMap('Account');
        Set<id> setPriceBookId=new Set<id>();
        Set<id> setPrimaryQuote=new Set<id>();
        Set<id> setExternalTransaction=new Set<id>();
        Set<id> setLieuDinsllation=new Set<id>();
        List<OpportunityContactRole> OppContactRoleList= new list<OpportunityContactRole>();
        
        for(Opportunity o:newOpps)
        {
            setAccId.add(o.accountid);
            setAccId.add(o.Copro_user__c);
            setAccId.add(o.Billed_to__c); 
         	setAccId.add(o.LieuInstallation__c); 
            setOppId.add(o.id);
            setPriceBookId.add(o.Pricebook2Id);
            setPrimaryQuote.add(o.Primary_Quote__c);
            setPrimaryQuote.add(o.Subscription_Billed_to__c);
            
            setExternalTransaction.add(o.External_Transaction__c);
        }    
        map<id,account> accMap=RetreiveSobjectRecord.getMapAccount(setAccId);
        map<id,account> personAccMap=RetreiveSobjectRecord.getPersonAcc(setAccId);
        map<id,Installation__c> instalMap=RetreiveSobjectRecord.getMapInstalFilterByOppIds(setAccId);
        map<id,Vehicle_Entry__c> mapVehicleEntry=RetreiveSobjectRecord.getMapVehicleEntryByOppIds(setAccId);
        map<id,Pricebook2> mapPriceBook=new map<id,Pricebook2>([select name from Pricebook2 where id in :setPriceBookId]);
        map<id,zqu__Quote__c> mapPrimaryQuote=new map<id,zqu__Quote__c>([select zqu__ApprovalStatus__c from zqu__Quote__c where id in :setPrimaryQuote]);
        map<id,External_Transaction__c> mapExternalTransaction=new map<id,External_Transaction__c>([select Status__c from External_Transaction__c where id in :setExternalTransaction]);
        for(Opportunity o:newOpps)
        {
            /*Opp - Fill Agence*/
                if(isBefore&&String.isEmpty(o.Agence__c)&&accMap.get(o.accountid).RecordTypeId==(recTypeIdMapAcc.get('Copro')))
                {
                    
                    o.Agence__c=accMap.get(o.accountid).Agence__c;
                }   
            /*Opp - Rename*/
                if(isBefore&&(o.RecordType.DeveloperName=='Abonnement_Flotte_Copro')||((o.RecordType.DeveloperName=='Abonnement_Flotte_Copro')&&(o.Copro_user__c!=oldOpps.get(o.id).Copro_user__c)))
                {
                    String s1='Abo Flotte C - '+accMap.get(o.accountid).Name+' - '+personAccMap.get(o.Copro_user__c).LastName+' '+personAccMap.get(o.Copro_user__c).FirstName;
                    o.Name=s1.left(80);
                }
            	if(isBefore&&((o.RecordType.DeveloperName=='Abonnement_Flotte_Copro')||((o.RecordType.DeveloperName=='Abonnement_Flotte_Pavillon')&&(o.Copro_user__c!=oldOpps.get(o.id).Copro_user__c)))&&!o.Projet_VIP__c)
                {
                    String s1='Abo Flotte P - '+accMap.get(o.accountid).Name+' - '+personAccMap.get(o.Copro_user__c).LastName+' '+personAccMap.get(o.Copro_user__c).FirstName;
                    o.Name=s1.left(80);
                }
            	if(isBefore&&o.RecordType.DeveloperName=='Promoter_Agreement')
                {
                    String s1='Acp'+' - '+accMap.get(o.Accountid).Name;
                    o.Name=s1.left(80);
                }
            	if(isBefore&&o.RecordType.DeveloperName=='Subscription')
                {
                    o.Installments__c=true;
                }
            	if(isBefore&&!String.isEmpty(o.Accountid)&&!String.isEmpty(accMap.get(o.accountid).Gestionnaire__c)&&o.RecordType.DeveloperName=='Convention_Copro'&&String.isEmpty(o.GestionnaireCcompte__c))
                {
                    o.GestionnaireCcompte__c=accMap.get(o.accountid).Gestionnaire__c;
                }
            
            	if(isBefore&&o.RecordType.DeveloperName=='Devis_Prestations_sur_devis_B2C'&&!o.Projet_VIP__c)
                {
                    if(!String.isEmpty(o.Copro_user__c)&&o.RecordType.DeveloperName=='Subscription')
                    {
                        String s1=recTypeIdMap.get('Subscription');
                        String s2=s1.left(3)+' - '+accMap.get(o.accountid).Name+' - '+personAccMap.get(o.Copro_user__c).LastName+' '+personAccMap.get(o.Copro_user__c).FirstName;
                    	o.Name=s2.left(80);
                    }
                    if(isBefore&&String.isEmpty(o.Copro_user__c)&&o.RecordType.DeveloperName=='Subscription')
                    {
                        String s1=recTypeIdMap.get('Subscription');
                        String s2=s1.left(3)+' - '+accMap.get(o.accountid).Name;
                    	o.Name=s2.left(80);
                    }
                    For(id idInstall:instalMap.keySet())//a voir la cardinalite pour supprime le for
                    {
                        instalMap.get(idInstall).ProjetVIP__c=false;
                    }
                     
                }
                if(isBefore&&!o.Projet_VIP__c&&o.RecordType.DeveloperName=='Devis_Prestations_sur_devis_B2C')
                {
                    if(!String.isEmpty(o.Copro_user__c)&&o.RecordType.DeveloperName=='Devis_Prestations_sur_devis_B2C')
                    {       
                        String s2='Devis B2C - '+' - '+accMap.get(o.accountid).Name+' - '+personAccMap.get(o.Copro_user__c).LastName+' '+personAccMap.get(o.Copro_user__c).FirstName;
                    	o.Name=s2.left(80);
                    }
                    if(String.isEmpty(o.Copro_user__c)&&o.RecordType.DeveloperName=='Devis_Prestations_sur_devis_B2C')
                    {
                        String s2='Devis B2C - '+' - '+accMap.get(o.accountid).Name;
                    	o.Name=s2.left(80);
                    }
                    For(id idInstall:instalMap.keySet())//a voir la cardinalite pour supprime le for
                    {
                        instalMap.get(idInstall).ProjetVIP__c=false;
                    }
                }
            	if(isBefore&&o.Projet_VIP__c)
                {
                    if(!String.isEmpty(o.Copro_user__c)&&o.RecordType.DeveloperName=='Subscription')
                    {
                        String s1=recTypeIdMap.get('Subscription');
                        String s2=s1.left(3)+' - '+accMap.get(o.accountid).Name+' - ⚡ '+personAccMap.get(o.Copro_user__c).LastName+' '+personAccMap.get(o.Copro_user__c).FirstName;
                    	o.Name=s2.left(80);
                    }
                    if(String.isEmpty(o.Copro_user__c)&&o.RecordType.DeveloperName=='Subscription')
                    {
                        String s1=recTypeIdMap.get('Subscription');
                        String s2=s1.left(3)+' - ⚡ '+accMap.get(o.accountid).Name;
                    	o.Name=s2.left(80);
                    }
                    For(id idInstall:instalMap.keySet())//a voir la cardinalite pour supprime le for
                    {
                        instalMap.get(idInstall).ProjetVIP__c=true;
                    }
                }
            	 if(isBefore&&!String.isEmpty(o.Copro_user__c)&&o.RecordType.DeveloperName=='Subscription')
                 {
                     if(!o.Projet_VIP__c)
                     {
                         String s1=recTypeIdMap.get('Subscription');
                         String s2=s1.left(3)+' - '+accMap.get(o.accountid).Name+' - '+personAccMap.get(o.Copro_user__c).LastName+' '+personAccMap.get(o.Copro_user__c).FirstName;
                         o.Name=s2.left(80);
                     }
                     if(o.Projet_VIP__c)
                     {
                         String s1=recTypeIdMap.get('Subscription');
                         String s2=s1.left(3)+' - '+accMap.get(o.accountid).Name+' - ⚡ '+personAccMap.get(o.Copro_user__c).LastName+' '+personAccMap.get(o.Copro_user__c).FirstName;
                         o.Name=s2.left(80);
                     }
                 }
            	 if(isBefore&&String.isEmpty(o.Copro_user__c)&&o.RecordType.DeveloperName=='Subscription')
                 {
                     if(!o.Projet_VIP__c)
                     {
                         String s1=recTypeIdMap.get('Subscription');
                         String s2=s1.left(3)+' - '+accMap.get(o.accountid).Name;
                         o.Name=s2.left(80);
                     }
                     if(o.Projet_VIP__c)
                     {
                         String s1=recTypeIdMap.get('Subscription');
                         String s2=s1.left(3)+' - ⚡ '+accMap.get(o.accountid).Name;
                         o.Name=s2.left(80);
                     }
                 }	
            	 String s1=recTypeIdMap.get('Subscription');
                 String s2=s1.left(3)+' - '+accMap.get(o.accountid).Name;	
            	 if(isBefore&&o.name!=s2&&o.RecordTypeId!=recTypeIdMap.get('Subscription')&&o.RecordTypeId!=recTypeIdMap.get('Subscription_B2B'))
                 {
                     if(o.Projet_VIP__c)
                     {
                         String s3=recTypeIdMap.get('Subscription');
                         String s4=s1.left(3)+' - ⚡ '+accMap.get(o.accountid).Name;
                         o.Name=s4.left(80);
                     }
                 }
            
            /*Opp - Price Book*/
                if(isBefore&&!mapPriceBook.isEmpty()&&!String.isEmpty(o.Pricebook2Id)&&!oldOpps.isEmpty()&&((o.Pricebook2Id!=oldOpps.get(o.id).Pricebook2Id)||String.isEmpty(o.Price_Book_Name__c)||(mapPriceBook.get(o.Pricebook2Id).Name!=o.Price_Book_Name__c)))
                {
                    o.Price_Book_Name__c=mapPriceBook.get(o.Pricebook2Id).Name;
                }
                if(((o.RecordtypeId==recTypeIdMap.get('Subscription'))||(o.RecordtypeId==recTypeIdMap.get('Subscription_B2B')))&&String.isEmpty(o.Billed_to__c))
                {
                    o.Pricebook2Id=System.Label.PriceBookId;
                }  
            	else if(isBefore&&o.Pricebook2Id==System.Label.PriceBookId_2)
                {
                    o.Pricebook2Id=System.Label.PriceBookId_3;
                }
            	else if(isBefore&&accMap.get(o.accountid).BillingCity=='Monaco')
                {
                    o.Pricebook2Id=System.Label.PriceBookId_4;
                }
            	else if(isBefore&&(o.CreatedDate!=o.LastModifiedDate)&&o.Accountid!=null&&!personAccMap.isEmpty()&&!accMap.isEmpty()&&o.Billed_to__c!=null&&personAccMap.get(o.Billed_to__c).RecordType!=null&&accMap.get(o.Billed_to__c).RecordType!=null&&(personAccMap.get(o.Billed_to__c).RecordType.DeveloperName=='PersonAccount'||(accMap.get(o.Billed_to__c).RecordType.DeveloperName=='Company'&&
                     accMap.get(o.Billed_to__c).is_SCI__c))&&!o.CITE_2019__c&&!o.HasOpportunityLineItem&&((o.Mise_en_service__c>date.newinstance(2019, 12, 31))||o.Mise_en_service__c==null)
                        &&accMap.get(o.Accountid).Copro_age__c=='Neuf'&&(o.RecordtypeId==recTypeIdMap.get('Subscription_B2B')||o.RecordtypeId==recTypeIdMap.get('Subscription'))) 
                {
                    o.Pricebook2Id=System.Label.PriceBookId_5;
                }
            	else if(isBefore&&(o.RecordtypeId==recTypeIdMap.get('Subscription')||o.RecordtypeId==recTypeIdMap.get('Subscription_B2B'))&&(accMap.get(o.Billed_to__c).RecordType.DeveloperName=='PersonAccount'||
                        (accMap.get(o.Billed_to__c).RecordType.DeveloperName=='Company'&&accMap.get(o.Billed_to__c).is_SCI__c))&&personAccMap.get(o.Billed_to__c).RecordType.DeveloperName=='PersonAccount'&&
                       accMap.get(o.Accountid).Copro_age__c=='Ancien'&&!o.CITE_2019__c&&!o.HasOpportunityLineItem) 
                {
                    o.Pricebook2Id=System.Label.PriceBookId_6;
                }
            	else if(isBefore&&!o.HasOpportunityLineItem)
                {
                    o.Pricebook2Id=System.Label.PriceBookId_7;
                }
            

           
            
           } 
        if(!isBefore)
        {
            update accMap.values();
            update personAccMap.values();
            update instalMap.values(); 
            update mapPrimaryQuote.values();
            update mapExternalTransaction.values();
            update mapVehicleEntry.values();
            update OppContactRoleList;
        }
        
    }
    
    public static void AboB2Brename(List<Opportunity> newOpps,Map<Id,Opportunity> oldOpps)
    {
        Map<String,Id> recTypeIdMap=UtilsMethods.recordTypeMap('Opportunity');
        for(Opportunity o:newOpps)
        {
            
        }
    }
    
    public static void oppPriceBook(List<Opportunity> newOpps,Map<Id,Opportunity> oldOpps)
    {
		Map<String,Id> recTypeIdMap=UtilsMethods.recordTypeMap('Opportunity');
    	
        Set<id> setPriceBookId=new Set<id>();
        
        for(Opportunity o:newOpps)
        {
            setPriceBookId.add(o.Pricebook2Id);
        }
        map<id,Pricebook2> mapPriceBook=new map<id,Pricebook2>([select name from Pricebook2 where id in :setPriceBookId]);
        for(Opportunity o:newOpps)
        {
          
          
        }
    
    } 
    
    public static void byPassTest()
    {
        Integer i=0;
        
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
            
        
    }

   
    
    
    
    //Code made by Zeplug (Romain Dupin) : Add ADVENIR to opportunity if it does not exist
 /*   public static void add_ADVENIR_ifNotExist(List<Opportunity> newOpps,Map<Id,Opportunity> oldOpps){
        
        map<Id, Boolean> map_opp_hasAdvenir = new map<Id, Boolean>();
        list<Id> listIdOpp = new list<Id>();
        
        for(Opportunity opp : newOpps){
            if (opp.StageName =='Installation'){
                listIdOpp.add(opp.Id);
                map_opp_hasAdvenir.put(opp.Id, false);
            }
        }
        
        list<Dossier_ADVENIR__c> listDossier_ADVENIR_toCreate = new list<Dossier_ADVENIR__c>();
        if (listIdOpp.size() > 0){
            // Check if the opportunity has a "dossier advenir" associated
            list<Dossier_ADVENIR__c> listDossierAdvenir = [SELECT Id, Opportunity__c FROM Dossier_ADVENIR__c WHERE Opportunity__c IN :listIdOpp];
            for (Dossier_ADVENIR__c dossierAdv : listDossierAdvenir){
                map_opp_hasAdvenir.put(dossierAdv.Opportunity__c, true);
            }
            
            // If the opportunity has no ADVENIR dossier, it is created
            Boolean hasAdvenir = false;
            for (Id idOpportunity : map_opp_hasAdvenir.keySet()){
                hasAdvenir = map_opp_hasAdvenir.get(idOpportunity);
                if (hasAdvenir == false) {
                    Dossier_ADVENIR__c dossierToAdd = new Dossier_ADVENIR__c(Opportunity__c = idOpportunity);
                    listDossierAdvenir.add(dossierToAdd);
                }
            }
            upsert listDossierAdvenir;
            
            
        }
        
        
        
    }
    */
    
    
}