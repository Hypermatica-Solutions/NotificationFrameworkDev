@IsTest
private class TemplateEngineTest {

    @IsTest
    static void testBasicTokenReplacement() {
        Map<String, Object> ctx = new Map<String, Object>{
            'Account_Name' => 'CDC Demo Co',
            'Owner_Name'   => 'Prajwal Pandgale'
        };

        String result = TemplateEngine.render('Hi {{{Owner_Name}}}, account {{{Account_Name}}} updated.', ctx);

        System.assertEquals('Hi Prajwal Pandgale, account CDC Demo Co updated.', result);
    }

    @IsTest
    static void testCaseInsensitiveTokenMatch() {
        Map<String, Object> ctx = new Map<String, Object>{
            'account_name' => 'Test Account'
        };

        // Token in template uses different casing than context key
        String result = TemplateEngine.render('{{{Account_Name}}}', ctx);

        System.assertEquals('Test Account', result);
    }

    @IsTest
    static void testUnresolvedTokenLeftVisible() {
        Map<String, Object> ctx = new Map<String, Object>{
            'Account_Name' => 'Test Co'
        };

        // Owner_Name not in context — should remain as {{{Owner_Name}}}
        String result = TemplateEngine.render('{{{Owner_Name}}}', ctx);

        System.assertEquals('{{{Owner_Name}}}', result);
    }

    @IsTest
    static void testMultipleTokensInSameTemplate() {
        Map<String, Object> ctx = new Map<String, Object>{
            'Account_Name'   => 'Acme',
            'AnnualRevenue'  => '1500000',
            'Changed_By'     => 'Admin'
        };

        String template = '{{{Account_Name}}} — Revenue: {{{AnnualRevenue}}} — By: {{{Changed_By}}}';
        String result   = TemplateEngine.render(template, ctx);

        System.assertEquals('Acme — Revenue: 1500000 — By: Admin', result);
    }

    @IsTest
    static void testNullContextReturnsTemplateUnchanged() {
        String template = 'Hello {{{Account_Name}}}';
        String result   = TemplateEngine.render(template, null);

        System.assertEquals(template, result);
    }

    @IsTest
    static void testEmptyContextReturnsTemplateUnchanged() {
        String template = 'Hello {{{Account_Name}}}';
        String result   = TemplateEngine.render(template, new Map<String, Object>());

        System.assertEquals(template, result);
    }

    @IsTest
    static void testBlankTemplateReturnsEmpty() {
        String result = TemplateEngine.render('', new Map<String, Object>{'key' => 'val'});
        System.assertEquals('', result);
    }

    @IsTest
    static void testNullValueInContextRendersEmpty() {
        Map<String, Object> ctx = new Map<String, Object>{
            'Account_Name' => null
        };

        String result = TemplateEngine.render('{{{Account_Name}}}', ctx);

        System.assertEquals('', result);
    }
}
