public with sharing class TemplateEngine {

    /**
     * Replaces every {{{token}}} in the template with the matching value from context.
     * Token lookup is case-insensitive.
     * Tokens with no matching key are left as-is so missing data is visible.
     *
     * @param template  raw template string, e.g. "Hi {{{Owner_Name}}}, ..."
     * @param context   map of token name → value built by the Router
     * @return          resolved string with all tokens replaced
     */
    public static String render(String template, Map<String, Object> context) {
        if (String.isBlank(template)) return template != null ? template : '';
        if (context == null || context.isEmpty()) return template;

        // Flatten context to lowercase String keys for case-insensitive lookup
        Map<String, String> lowerCtx = new Map<String, String>();
        for (String key : context.keySet()) {
            Object val = context.get(key);
            lowerCtx.put(key.toLowerCase(), val != null ? String.valueOf(val) : '');
        }

        // Find every {{{token}}} and replace it
        String result = template;
        Matcher m = Pattern.compile('\\{\\{\\{([^}]+)\\}\\}\\}').matcher(template);

        while (m.find()) {
            String token = m.group(1).trim();
            String replacement = lowerCtx.containsKey(token.toLowerCase())
                ? lowerCtx.get(token.toLowerCase())
                : '{{{' + token + '}}}'; // leave unresolved so it is visible during development

            result = result.replace('{{{' + token + '}}}', replacement);
        }

        return result;
    }
}
