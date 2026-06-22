trigger AccountChangeEventTrigger on AccountChangeEvent (after insert) {
    // Debug — keep visible so we can confirm CDC fires in logs
    for (AccountChangeEvent event : Trigger.new) {
        EventBus.ChangeEventHeader header = event.ChangeEventHeader;
        system.debug('=== CDC ===' + header);
        System.debug('Change Type:    ' + header.changeType);
        System.debug('Changed Fields: ' + header.changedFields);
        System.debug('Record IDs:     ' + header.recordIds);
        System.debug('Changed By:     ' + header.commitUser);
        System.debug('=================');
    }

    // Hand off to the notification framework
    NotificationDispatcher.dispatch(Trigger.new, 'Account');
}
