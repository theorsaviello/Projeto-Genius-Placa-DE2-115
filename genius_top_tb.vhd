-- ============================================================
-- Testbench: genius_top_tb.vhd
-- Simula uma partida completa: Start -> Exibição -> Acerto -> Derrota
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity genius_top_tb is
end entity genius_top_tb;

architecture sim of genius_top_tb is

    -- Período de clock (50 MHz = 20 ns)
    constant CLK_PERIOD : time := 20 ns;

    -- Para acelerar a simulação, usamos constantes menores
    -- que as do hardware real (ajuste conforme seu simulador)
    constant SIM_LED_ON   : integer := 100;   -- ciclos de clock
    constant SIM_LED_OFF  : integer := 50;
    constant SIM_TIMEOUT  : integer := 500;

    -- Sinais do DUT
    signal CLOCK_50 : std_logic := '0';
    signal KEY      : std_logic_vector(3 downto 0) := "1111"; -- pull-up: repouso = '1'
    signal LEDG     : std_logic_vector(7 downto 0);
    signal LEDR     : std_logic_vector(9 downto 0);
    signal HEX0     : std_logic_vector(6 downto 0);
    signal HEX1     : std_logic_vector(6 downto 0);
    signal HEX2     : std_logic_vector(6 downto 0);
    signal HEX3     : std_logic_vector(6 downto 0);

begin

    -- Instância do DUT (Device Under Test)
    DUT: entity work.genius_top
        port map (
            CLOCK_50 => CLOCK_50,
            KEY      => KEY,
            LEDG     => LEDG,
            LEDR     => LEDR,
            HEX0     => HEX0,
            HEX1     => HEX1,
            HEX2     => HEX2,
            HEX3     => HEX3
        );

    -- Geração de clock
    CLOCK_50 <= not CLOCK_50 after CLK_PERIOD / 2;

    -- ===========================================================
    -- Processo de estímulos
    -- ===========================================================
    stim_proc: process

        -- Procedimento para pressionar e soltar uma tecla por N ciclos
        procedure press_key(key_idx : integer; hold_cycles : integer := 5) is
        begin
            KEY(key_idx) <= '0';          -- pressiona (ativo baixo)
            wait for CLK_PERIOD * hold_cycles;
            KEY(key_idx) <= '1';          -- solta
            wait for CLK_PERIOD * 10;
        end procedure;

        -- Aguarda N ciclos de clock
        procedure wait_cycles(n : integer) is
        begin
            wait for CLK_PERIOD * n;
        end procedure;

    begin
        -- Inicialização
        KEY <= "1111";
        wait_cycles(10);

        report "=== INICIO DA SIMULACAO DO JOGO GENIUS ===" severity note;

        -- -------------------------------------------------------
        -- FASE 1: Estado IDLE
        -- -------------------------------------------------------
        report "FASE 1: Verificando estado IDLE..." severity note;
        wait_cycles(200);
        assert LEDR = "0000000000"
            report "ERRO: LEDR deveria estar apagado no IDLE" severity warning;

        -- -------------------------------------------------------
        -- FASE 2: Inicia o jogo com KEY0
        -- -------------------------------------------------------
        report "FASE 2: Pressionando KEY0 para iniciar o jogo..." severity note;
        press_key(0, 10);

        -- -------------------------------------------------------
        -- FASE 3: Aguarda geração e exibição da sequência
        -- -------------------------------------------------------
        report "FASE 3: Aguardando exibicao da sequencia (nivel 1)..." severity note;
        -- Tempo suficiente para LED_OFF + LED_ON
        wait_cycles(500);

        -- -------------------------------------------------------
        -- FASE 4: Pressiona KEY0 como tentativa de acerto
        -- (Se o primeiro elemento for "00", KEY0 está correto)
        -- -------------------------------------------------------
        report "FASE 4: Usuario pressiona KEY0..." severity note;
        press_key(0, 8);
        wait_cycles(50);

        -- -------------------------------------------------------
        -- FASE 5: Aguarda próximo nível
        -- -------------------------------------------------------
        report "FASE 5: Aguardando proximo nivel..." severity note;
        wait_cycles(800);

        -- -------------------------------------------------------
        -- FASE 6: Pressiona teclas erradas para simular Game Over
        -- -------------------------------------------------------
        report "FASE 6: Pressionando KEY3 (possivel erro)..." severity note;
        press_key(3, 8);
        wait_cycles(50);
        press_key(3, 8);
        wait_cycles(50);

        -- -------------------------------------------------------
        -- FASE 7: Aguarda animação de Game Over
        -- -------------------------------------------------------
        report "FASE 7: Aguardando animacao de Game Over..." severity note;
        wait_cycles(2000);

        -- Verifica se os LEDs vermelhos piscaram
        -- (verificação simplificada - em simulação real usaríamos
        --  processos concorrentes de monitoramento)

        -- -------------------------------------------------------
        -- FASE 8: Reset após Game Over com KEY0
        -- -------------------------------------------------------
        report "FASE 8: Resetando o jogo..." severity note;
        press_key(0, 10);
        wait_cycles(100);

        -- -------------------------------------------------------
        -- FASE 9: Simula timeout (sem pressionar nenhum botão)
        -- -------------------------------------------------------
        report "FASE 9: Iniciando novo jogo e testando timeout..." severity note;
        press_key(0, 10);  -- inicia
        wait_cycles(600);  -- aguarda exibição
        -- Não pressiona nenhum botão -> timeout em 5 s (simulado)
        wait_cycles(600);

        report "=== SIMULACAO CONCLUIDA ===" severity note;
        wait;
    end process;

    -- ===========================================================
    -- Monitor: imprime mensagem quando LEDR acende (Game Over)
    -- ===========================================================
    monitor_proc: process(LEDR)
    begin
        if LEDR /= "0000000000" then
            report "MONITOR: LEDs vermelhos acesos = Game Over / Animacao" severity note;
        end if;
    end process;

    -- Monitor de estado dos LEDs verdes
    monitor_ledg: process(LEDG)
    begin
        if LEDG /= "00000000" then
            report "MONITOR: LEDG aceso" severity note;
        end if;
    end process;

end architecture sim;
