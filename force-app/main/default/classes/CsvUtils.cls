public with sharing class CsvUtils {

    public static String escape(Object input) {
        if (input == null) return '';
        String s = String.valueOf(input);
        if (s.startsWith('(') && s.endsWith(')')) s = s.substring(1, s.length() - 1);
        s = s.replace('\r', ' ').replace('\n', ' ');
        Boolean needQuotes = s.contains(',') || s.contains('"');
        if (s.contains('"')) s = s.replace('"', '""');
        if (needQuotes) s = '"' + s + '"';
        return s;
    }   
   
    public static List<String> parseLine(String line) {
        List<String> result = new List<String>();
        Boolean inQuotes = false;
        String current = '';

        for (Integer i = 0; i < line.length(); i++) {
            String c = line.substring(i, i + 1);

            if (c == '"') {
                // gestion des guillemets échappés ""
                if (inQuotes && i + 1 < line.length() && line.substring(i + 1, i + 2) == '"') {
                    current += '"';
                    i++;
                } else {
                    inQuotes = !inQuotes;
                }
            } else if (c == ',' && !inQuotes) {
                result.add(current);
                current = '';
            } else {
                current += c;
            }
        }
        result.add(current);
        return result;
    }

    public static List<List<String>> parse(String csv) {
        List<List<String>> rows = new List<List<String>>();
        for (String line : csv.replace('\r\n', '\n').replace('\r', '\n').split('\n')) {
            if (!String.isBlank(line)) {
                rows.add(parseLine(line));
            }
        }
        return rows;
    }


}