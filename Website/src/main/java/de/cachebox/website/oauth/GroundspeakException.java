package de.cachebox.website.oauth;

/** Only fixed, user-facing messages; never include provider bodies, codes or credentials. */
public class GroundspeakException extends RuntimeException {
    GroundspeakException(String message) { super(message); }
}
