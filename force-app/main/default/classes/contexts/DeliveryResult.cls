global with sharing class DeliveryResult {
    global Map<Id, RecipientResult> resultsByRecipient = new Map<Id, RecipientResult>();

    global class RecipientResult {
        global Boolean success;
        global String errorMessage;
        global DateTime sentAt;
    }
}
