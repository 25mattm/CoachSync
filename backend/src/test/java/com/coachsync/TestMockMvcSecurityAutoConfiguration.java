package com.coachsync;

import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnClass;
import org.springframework.boot.webmvc.test.autoconfigure.MockMvcBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers;

/**
 * Test-only auto-configuration. Spring Boot 4's {@code spring-boot-webmvc-test} slice no
 * longer auto-applies Spring Security's MockMvc configurer, so {@code @WithMockUser} and
 * the {@code jwt()} request post-processors would be ignored and every secured request
 * would 401. Registering this {@link MockMvcBuilderCustomizer} re-applies
 * {@code springSecurity()} to every auto-configured {@code MockMvc}.
 *
 * <p>Loaded globally via {@code META-INF/spring/.../AutoConfiguration.imports} on the test
 * classpath, so no per-test wiring is needed. The customizer is only consumed by
 * {@code MockMvcAutoConfiguration} (i.e. {@code @AutoConfigureMockMvc} tests); non-web
 * contexts create the bean but never invoke it.
 */
@AutoConfiguration
@ConditionalOnClass(SecurityMockMvcConfigurers.class)
public class TestMockMvcSecurityAutoConfiguration {

    @Bean
    MockMvcBuilderCustomizer securityMockMvcBuilderCustomizer() {
        return builder -> builder.apply(SecurityMockMvcConfigurers.springSecurity());
    }
}
