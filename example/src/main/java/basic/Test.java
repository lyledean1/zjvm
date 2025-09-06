public class Test {
    public static final String STRING_CONSTANT = "foo bar";
    
    public static void main(String[] args) {
        Printer printer = new Printer(42);
        Calculator calculator = new Calculator();
        printer.print(STRING_CONSTANT);
        printer.print(calculator.add(21,33));
        printer.print(calculator.sub(44,33));
        printer.print(calculator.mul(3,3));
        printer.print(calculator.div(9,3));
        printer.print(calculator.rem(8,3));
        printer.print(true, true);
        printer.print(false, true);
    }
}